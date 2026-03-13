#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
. "$(dirname "$0")/_lib.sh"

VAULT_FQDN="vault-0.vault.${NAMESPACE}.svc.cluster.local"

VAULT_ROOT_TOKEN=$(cat "$SECRETS_DIR/vault-bootstrap-token")

vault_cmd() {
  $KUBECTL exec vault-0 -n "$NAMESPACE" -c vault -- sh -c "
    VAULT_ADDR=https://${VAULT_FQDN}:8200 \
    VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
    VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
    $1
  "
}

# --- Create Vault Policy ---
echo "Creating Vault policy for cabotage-app..."
POLICY=$(cat "$VAULT_POLICY_FILE")
printf '%s' "$POLICY" | $KUBECTL exec -i vault-0 -n "$NAMESPACE" -c vault -- sh -c "
  VAULT_ADDR=https://${VAULT_FQDN}:8200 \
  VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
  VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
  vault policy write cabotage-cabotage-app -
" || { echo "Failed: vault policy write"; exit 1; }

# --- Create Kubernetes Auth Role ---
echo "Creating vault-kubernetes-auth binding for cabotage-app..."
vault_cmd "vault write auth/kubernetes/role/cabotage-cabotage-app \
  bound_service_account_names=cabotage-app \
  bound_service_account_namespaces=cabotage \
  policies=cabotage-cabotage-app \
  ttl=21600 max_ttl=21600 period=21600" || { echo "Failed: vault kubernetes auth role"; exit 1; }

# --- Create Consul Policy & Role ---
echo "Creating Consul policy and role for cabotage-app..."
CONSUL_MGMT_TOKEN=$(cat "$SECRETS_DIR/consul-bootstrap-token")
CONSUL_POLICY=$(cat "$CONSUL_POLICY_FILE")

# Create or update consul policy via Vault's consul backend
vault_cmd "vault write cabotage-consul/roles/cabotage-cabotage-app \
  consul_policies=cabotage-cabotage-app \
  ttl=6h \
  local=true" || { echo "Failed: vault consul role"; exit 1; }

# Create the consul policy directly
$KUBECTL exec consul-0 -n "$NAMESPACE" -c consul -- sh -c "
  curl --silent --show-error --fail \
    --header 'X-Consul-Token: $CONSUL_MGMT_TOKEN' \
    --request PUT \
    --data '{\"Name\": \"cabotage-cabotage-app\", \"Rules\": $(printf '%s' "$CONSUL_POLICY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")}' \
    http://127.0.0.1:8500/v1/acl/policy || \
  curl --silent --show-error \
    --header 'X-Consul-Token: $CONSUL_MGMT_TOKEN' \
    --request PUT \
    --data '{\"Name\": \"cabotage-cabotage-app\", \"Rules\": $(printf '%s' "$CONSUL_POLICY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")}' \
    http://127.0.0.1:8500/v1/acl/policy/name/cabotage-cabotage-app
" || echo "Consul policy may already exist"

# --- Enable Transit Backend ---
echo "Enabling transit backend for cabotage-app..."
vault_cmd "vault secrets enable \
  -path=cabotage-app-transit \
  -description='transit backend for cabotage-app' \
  transit" || echo "Transit backend may already be enabled."

# --- Create Transit Key ---
echo "Creating registry transit key..."
vault_cmd "vault write -f cabotage-app-transit/keys/registry type=ecdsa-p256" || echo "Transit key may already exist."

echo "Cabotage app bootstrap complete!"
