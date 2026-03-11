#!/bin/sh
set -e

CONSUL_HTTP="http://consul-0.consul.cabotage.svc.cluster.local:8500"
KUBE_API="https://kubernetes.default.svc"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBE_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE="cabotage"

kube_get_secret() {
  curl -s --cacert "$KUBE_CA" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    "$KUBE_API/api/v1/namespaces/$NAMESPACE/secrets/$1"
}

kube_patch_secret() {
  local name=$1 key=$2 value=$3
  local b64=$(printf '%s' "$value" | base64)
  curl -s --cacert "$KUBE_CA" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    -H "Content-Type: application/strategic-merge-patch+json" \
    -X PATCH \
    -d "{\"data\":{\"$key\":\"$b64\"}}" \
    "$KUBE_API/api/v1/namespaces/$NAMESPACE/secrets/$name"
}

# --- Wait for Consul ---
echo "Waiting for Consul leader..."
until curl -sf "$CONSUL_HTTP/v1/status/leader" | grep -q '"'; do
  echo "  not ready, retrying in 5s..."
  sleep 5
done
echo "Consul is ready."

# --- Bootstrap ACLs ---
# Check if we already have a management token stored
stored=$(kube_get_secret consul-management-token | \
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
stored_decoded=$(printf '%s' "$stored" | base64 -d 2>/dev/null || echo "null")

if [ "$stored_decoded" != "null" ] && [ -n "$stored_decoded" ]; then
  echo "Management token already exists in secret."
  MGMT_TOKEN="$stored_decoded"
else
  echo "Bootstrapping ACLs..."
  response=$(curl -sf -X PUT "$CONSUL_HTTP/v1/acl/bootstrap" 2>&1) || {
    echo "ACL bootstrap failed (may already be bootstrapped)."
    echo "Store the management token in the consul-management-token secret and re-run."
    echo "$response"
    exit 1
  }
  MGMT_TOKEN=$(printf '%s' "$response" | sed -n 's/.*"SecretID"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  echo "ACL bootstrap successful. Storing management token..."
  kube_patch_secret consul-management-token token "$MGMT_TOKEN" > /dev/null
fi

# --- Anonymous policy ---
echo "Creating anonymous policy..."
curl -sf -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Name":"anonymous","Rules":"node_prefix \"\" { policy = \"read\" }\nservice_prefix \"\" { policy = \"read\" }\noperator = \"read\""}' \
  "$CONSUL_HTTP/v1/acl/policy" > /dev/null || echo "  (may already exist)"

curl -sf -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Policies":[{"Name":"anonymous"}]}' \
  "$CONSUL_HTTP/v1/acl/token/00000000-0000-0000-0000-000000000002" > /dev/null
echo "Anonymous policy applied."

# --- Agent policy + token ---
stored_agent=$(kube_get_secret consul-agent-token | \
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
stored_agent_decoded=$(printf '%s' "$stored_agent" | base64 -d 2>/dev/null || echo "null")

if [ "$stored_agent_decoded" != "null" ] && [ -n "$stored_agent_decoded" ]; then
  echo "Agent token already exists."
  AGENT_TOKEN="$stored_agent_decoded"
else
  echo "Creating agent policy and token..."
  curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"agent","Rules":"node_prefix \"\" { policy = \"write\" }\nservice_prefix \"\" { policy = \"write\" }"}' \
    "$CONSUL_HTTP/v1/acl/policy" > /dev/null || echo "  (policy may already exist)"

  response=$(curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Agent Token","Policies":[{"Name":"agent"}],"Local":true}' \
    "$CONSUL_HTTP/v1/acl/token")
  AGENT_TOKEN=$(printf '%s' "$response" | sed -n 's/.*"SecretID"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  kube_patch_secret consul-agent-token token "$AGENT_TOKEN" > /dev/null
  echo "Agent token created and stored."
fi

# Apply agent token to all servers
echo "Applying agent token to cluster members..."
for i in 0 1 2; do
  curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d "{\"Token\":\"$AGENT_TOKEN\"}" \
    "http://consul-$i.consul.cabotage.svc.cluster.local:8500/v1/agent/token/agent" > /dev/null
  echo "  Applied to consul-$i"
done

# --- Vault policy + token ---
stored_vault=$(kube_get_secret vault-consul-token | \
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
stored_vault_decoded=$(printf '%s' "$stored_vault" | base64 -d 2>/dev/null || echo "null")

if [ "$stored_vault_decoded" != "null" ] && [ -n "$stored_vault_decoded" ]; then
  echo "Vault consul token already exists."
else
  echo "Creating vault policy and token..."
  curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"vault","Rules":"key_prefix \"vault/\" { policy = \"write\" }\nnode_prefix \"vault-\" { policy = \"write\" }\nservice \"vault\" { policy = \"write\" }\nagent_prefix \"vault-\" { policy = \"write\" }\nsession_prefix \"vault-\" { policy = \"write\" }"}' \
    "$CONSUL_HTTP/v1/acl/policy" > /dev/null || echo "  (policy may already exist)"

  response=$(curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Vault Server Token","Policies":[{"Name":"vault"}],"Local":true}' \
    "$CONSUL_HTTP/v1/acl/token")
  VAULT_TOKEN=$(printf '%s' "$response" | sed -n 's/.*"SecretID"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  kube_patch_secret vault-consul-token token "$VAULT_TOKEN" > /dev/null
  echo "Vault consul token created and stored."
fi

echo "Bootstrap complete!"
