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
echo "Creating Vault policy for cabotage-enrollment-operator..."
POLICY=$(cat "$POLICY_FILE")
printf '%s' "$POLICY" | $KUBECTL exec -i vault-0 -n "$NAMESPACE" -c vault -- sh -c "
  VAULT_ADDR=https://${VAULT_FQDN}:8200 \
  VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
  VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
  vault policy write cabotage-enrollment-operator -
" || { echo "Failed: vault policy write for enrollment-operator"; exit 1; }

# --- Create Kubernetes Auth Role ---
echo "Creating vault-kubernetes-auth binding for cabotage-enrollment-operator..."
vault_cmd "vault write auth/kubernetes/role/cabotage-enrollment-operator \
  bound_service_account_names=enrollment-operator \
  bound_service_account_namespaces=cabotage \
  policies=cabotage-enrollment-operator \
  ttl=21600 max_ttl=21600 period=21600" || { echo "Failed: vault kubernetes auth role for enrollment-operator"; exit 1; }

# --- Create Consul Secret Backend Role ---
echo "Configuring enrollment-operator role for Consul Secret Backend..."
vault_cmd "vault write cabotage-consul/roles/cabotage-enrollment-operator \
  consul_policies=global-management \
  ttl=1h \
  local=true" || { echo "Failed: vault consul role for enrollment-operator"; exit 1; }

echo "Enrollment operator bootstrap complete!"
