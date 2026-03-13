#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
CONSUL_REPLICAS="${CONSUL_REPLICAS:-3}"
CONSUL_LOCAL_PORT="${CONSUL_LOCAL_PORT:-18500}"
export CONSUL_LOCAL_PORT
. "$(dirname "$0")/_lib.sh"
PF_PID=""

cleanup() {
  [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

# --- Wait for consul-0 and start port-forward ---
echo "Waiting for consul-0..."
while ! $KUBECTL get pod consul-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; do
  sleep 5
done

# Kill any stale port-forward on 18500 from a previous run
kill_port "$CONSUL_LOCAL_PORT"

$KUBECTL port-forward pod/consul-0 "${CONSUL_LOCAL_PORT}:8500" -n "$NAMESPACE" > /dev/null 2>&1 &
PF_PID=$!

echo "Waiting for port-forward to be ready..."
wait_for 30 2 curl -sf http://localhost:${CONSUL_LOCAL_PORT}/v1/status/leader

echo "Waiting for Consul leader..."
wait_for 120 5 sh -c "curl -sf http://localhost:\${CONSUL_LOCAL_PORT}/v1/status/leader | grep -q '.:' "
echo "Consul is ready."

# --- Bootstrap ACLs ---
echo "Bootstrapping ACLs..."
MGMT_TOKEN=""

# Try bootstrap first
response=$(curl -sf -X PUT http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/bootstrap 2>&1) && {
  MGMT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')
  mkdir -p "$SECRETS_DIR"
  printf '%s' "$MGMT_TOKEN" > "$SECRETS_DIR/consul-bootstrap-token"
  chmod 600 "$SECRETS_DIR/consul-bootstrap-token"
  echo "Management token saved to $SECRETS_DIR/consul-bootstrap-token"
}

# If bootstrap didn't give us a token, try loading from file
if [ -z "$MGMT_TOKEN" ] || [ "$MGMT_TOKEN" = "null" ]; then
  if [ -f "$SECRETS_DIR/consul-bootstrap-token" ]; then
    MGMT_TOKEN=$(cat "$SECRETS_DIR/consul-bootstrap-token")
    echo "Bootstrap already done, loaded token from file. Verifying..."
    # Verify the saved token actually works on this cluster
    if ! curl -sf -H "X-Consul-Token: $MGMT_TOKEN" http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/self > /dev/null 2>&1; then
      echo "Saved token is STALE (wrong cluster?). Removing and re-bootstrapping..."
      rm -f "$SECRETS_DIR/consul-bootstrap-token"
      MGMT_TOKEN=""
      response=$(curl -sf -X PUT http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/bootstrap 2>&1) || {
        echo "ACL bootstrap failed and stale token was removed. Cannot proceed."
        echo "If Consul was already bootstrapped on this cluster, the token is lost."
        exit 1
      }
      MGMT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')
      mkdir -p "$SECRETS_DIR"
      printf '%s' "$MGMT_TOKEN" > "$SECRETS_DIR/consul-bootstrap-token"
      chmod 600 "$SECRETS_DIR/consul-bootstrap-token"
      echo "Re-bootstrapped. New management token saved."
    else
      echo "Token verified OK."
    fi
  else
    echo "ACL bootstrap failed and no existing token found."
    exit 1
  fi
fi

# --- Anonymous policy ---
echo "Creating anonymous policy..."
# Try creating, if it already exists update it by name
curl_api -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Name":"anonymous","Rules":"node_prefix \"\" { policy = \"read\" }\nservice_prefix \"\" { policy = \"read\" }\noperator = \"read\""}' \
  http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/policy > /dev/null || \
curl_api -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Rules":"node_prefix \"\" { policy = \"read\" }\nservice_prefix \"\" { policy = \"read\" }\noperator = \"read\""}' \
  "http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/policy/name/anonymous" > /dev/null || echo "  (anonymous policy may already exist)"

# Update the anonymous token to use the policy
curl_api -X PUT \
  -H "X-Consul-Token: $MGMT_TOKEN" \
  -d '{"Policies":[{"Name":"anonymous"}]}' \
  "http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/00000000-0000-0000-0000-000000000002" > /dev/null || echo "  (anonymous token update may have already been applied)"
echo "Anonymous policy applied."

# --- Agent policy + token ---
AGENT_TOKEN=$($KUBECTL get secret consul-agent-token -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
[ "$AGENT_TOKEN" = "null" ] && AGENT_TOKEN=""

# Verify the token is valid by checking it against Consul
if [ -n "$AGENT_TOKEN" ] && curl -sf -H "X-Consul-Token: $AGENT_TOKEN" http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/self > /dev/null 2>&1; then
  echo "Agent token already exists and is valid."
else
  echo "Creating agent policy and token..."
  curl_api -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"agent","Rules":"node_prefix \"\" { policy = \"write\" }\nservice_prefix \"\" { policy = \"write\" }"}' \
    http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/policy > /dev/null || echo "  (policy may already exist)"

  response=$(curl_api -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Agent Token","Policies":[{"Name":"agent"}],"Local":true}' \
    http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token) || {
    echo "  Token creation failed, looking for existing agent token..."
    ACCESSOR_ID=$(curl_api -H "X-Consul-Token: $MGMT_TOKEN" \
      http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/tokens | jq -r '.[] | select(.Description=="Agent Token") | .AccessorID')
    if [ -n "$ACCESSOR_ID" ]; then
      AGENT_TOKEN=$(curl_api -H "X-Consul-Token: $MGMT_TOKEN" \
        "http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/$ACCESSOR_ID" | jq -r '.SecretID')
    fi
  }
  if [ -z "$AGENT_TOKEN" ]; then
    AGENT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')
  fi

  if [ -z "$AGENT_TOKEN" ] || [ "$AGENT_TOKEN" = "null" ]; then
    echo "Could not create or find agent token"
    exit 1
  fi

  $KUBECTL patch secret consul-agent-token -n "$NAMESPACE" --type merge \
    -p "{\"data\":{\"token\":\"$(printf '%s' "$AGENT_TOKEN" | base64)\"}}"
  echo "Agent token saved."
fi

# Apply agent token to all servers
echo "Applying agent token to cluster members..."
for i in $(seq 0 $((CONSUL_REPLICAS - 1))); do
  $KUBECTL exec "consul-$i" -n "$NAMESPACE" -c consul -- sh -c \
    "CONSUL_HTTP_TOKEN='$MGMT_TOKEN' consul acl set-agent-token agent '$AGENT_TOKEN'" \
    2>/dev/null && echo "  Applied to consul-$i" \
    || echo "  consul-$i not reachable, skipping."
done

# --- Vault policy + token ---
VAULT_TOKEN=$($KUBECTL get secret vault-consul-token -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
[ "$VAULT_TOKEN" = "null" ] && VAULT_TOKEN=""

if [ -n "$VAULT_TOKEN" ] && curl -sf -H "X-Consul-Token: $VAULT_TOKEN" http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/self > /dev/null 2>&1; then
  echo "Vault consul token already exists and is valid."
else
  echo "Creating vault policy and token..."
  curl_api -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Name":"vault","Rules":"key_prefix \"vault/\" { policy = \"write\" }\nnode_prefix \"vault-\" { policy = \"write\" }\nservice \"vault\" { policy = \"write\" }\nagent_prefix \"vault-\" { policy = \"write\" }\nsession_prefix \"vault-\" { policy = \"write\" }"}' \
    http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/policy > /dev/null || echo "  (policy may already exist)"

  response=$(curl_api -X PUT \
    -H "X-Consul-Token: $MGMT_TOKEN" \
    -d '{"Description":"Vault Server Token","Policies":[{"Name":"vault"}],"Local":true}' \
    http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token) || {
    echo "  Token creation failed, looking for existing vault token..."
    ACCESSOR_ID=$(curl_api -H "X-Consul-Token: $MGMT_TOKEN" \
      http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/tokens | jq -r '.[] | select(.Description=="Vault Server Token") | .AccessorID')
    if [ -n "$ACCESSOR_ID" ]; then
      VAULT_TOKEN=$(curl_api -H "X-Consul-Token: $MGMT_TOKEN" \
        "http://localhost:${CONSUL_LOCAL_PORT}/v1/acl/token/$ACCESSOR_ID" | jq -r '.SecretID')
    fi
  }
  if [ -z "$VAULT_TOKEN" ]; then
    VAULT_TOKEN=$(printf '%s' "$response" | jq -r '.SecretID')
  fi

  if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
    echo "Could not create or find vault token"
    exit 1
  fi

  $KUBECTL patch secret vault-consul-token -n "$NAMESPACE" --type merge \
    -p "{\"data\":{\"token\":\"$(printf '%s' "$VAULT_TOKEN" | base64)\"}}"
  echo "Vault consul token saved."
fi

echo "Consul bootstrap complete!"
