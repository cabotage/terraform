#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
CONSUL_REPLICAS="${CONSUL_REPLICAS:-3}"
PF_PID=""

cleanup() {
  [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

# --- Wait for consul-0 and start port-forward ---
echo "Waiting for consul-0..."
while ! kubectl get pod consul-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; do
  sleep 5
done

kubectl port-forward pod/consul-0 18500:8500 -n "$NAMESPACE" > /dev/null 2>&1 &
PF_PID=$!
sleep 3

echo "Waiting for Consul leader..."
until curl -sf http://localhost:18500/v1/status/leader 2>/dev/null | grep -q '"'; do
  sleep 5
done
echo "Consul is ready."

# --- Bootstrap ACLs ---
echo "Bootstrapping ACLs..."
response=$(curl -sf -X PUT http://localhost:18500/v1/acl/bootstrap 2>&1) || {
  if [ -f "$SECRETS_DIR/consul-bootstrap-token" ]; then
    MGMT_TOKEN=$(cat "$SECRETS_DIR/consul-bootstrap-token")
    echo "Already bootstrapped, using existing token."
  else
    echo "ACL bootstrap failed and no existing token found."
    exit 1
  fi
}
if [ -z "$MGMT_TOKEN" ]; then
  MGMT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')
  mkdir -p "$SECRETS_DIR"
  printf '%s' "$MGMT_TOKEN" > "$SECRETS_DIR/consul-bootstrap-token"
  chmod 600 "$SECRETS_DIR/consul-bootstrap-token"
  echo "Management token saved to $SECRETS_DIR/consul-bootstrap-token"
fi

# --- Anonymous policy ---
echo "Creating anonymous policy..."
curl -sf -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Name":"anonymous","Rules":"node_prefix \"\" { policy = \"read\" }\nservice_prefix \"\" { policy = \"read\" }\noperator = \"read\""}' \
  http://localhost:18500/v1/acl/policy > /dev/null 2>&1 || echo "  (may already exist)"

curl -sf -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Policies":[{"Name":"anonymous"}]}' \
  "http://localhost:18500/v1/acl/token/00000000-0000-0000-0000-000000000002" > /dev/null
echo "Anonymous policy applied."

# --- Agent policy + token ---
AGENT_TOKEN=$(kubectl get secret consul-agent-token -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "null")

if [ "$AGENT_TOKEN" != "null" ] && [ -n "$AGENT_TOKEN" ]; then
  echo "Agent token already exists."
else
  echo "Creating agent policy and token..."
  curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"agent","Rules":"node_prefix \"\" { policy = \"write\" }\nservice_prefix \"\" { policy = \"write\" }"}' \
    http://localhost:18500/v1/acl/policy > /dev/null 2>&1 || echo "  (policy may already exist)"

  response=$(curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Agent Token","Policies":[{"Name":"agent"}],"Local":true}' \
    http://localhost:18500/v1/acl/token)
  AGENT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')

  kubectl patch secret consul-agent-token -n "$NAMESPACE" --type merge \
    -p "{\"data\":{\"token\":\"$(printf '%s' "$AGENT_TOKEN" | base64)\"}}"
  echo "Agent token created."
fi

# Apply agent token to all servers
echo "Applying agent token to cluster members..."
for i in $(seq 0 $((CONSUL_REPLICAS - 1))); do
  kubectl exec "consul-$i" -n "$NAMESPACE" -c consul -- sh -c \
    "CONSUL_HTTP_TOKEN='$MGMT_TOKEN' consul acl set-agent-token agent '$AGENT_TOKEN'" \
    2>/dev/null && echo "  Applied to consul-$i" \
    || echo "  consul-$i not reachable, skipping."
done

# --- Vault policy + token ---
VAULT_TOKEN=$(kubectl get secret vault-consul-token -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "null")

if [ "$VAULT_TOKEN" != "null" ] && [ -n "$VAULT_TOKEN" ]; then
  echo "Vault consul token already exists."
else
  echo "Creating vault policy and token..."
  curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"vault","Rules":"key_prefix \"vault/\" { policy = \"write\" }\nnode_prefix \"vault-\" { policy = \"write\" }\nservice \"vault\" { policy = \"write\" }\nagent_prefix \"vault-\" { policy = \"write\" }\nsession_prefix \"vault-\" { policy = \"write\" }"}' \
    http://localhost:18500/v1/acl/policy > /dev/null 2>&1 || echo "  (policy may already exist)"

  response=$(curl -sf -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Vault Server Token","Policies":[{"Name":"vault"}],"Local":true}' \
    http://localhost:18500/v1/acl/token)
  VAULT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')

  kubectl patch secret vault-consul-token -n "$NAMESPACE" --type merge \
    -p "{\"data\":{\"token\":\"$(printf '%s' "$VAULT_TOKEN" | base64)\"}}"
  echo "Vault consul token created."
fi

echo "Consul bootstrap complete!"
