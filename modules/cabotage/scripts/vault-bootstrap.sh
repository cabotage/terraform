#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
VAULT_REPLICAS="${VAULT_REPLICAS:-3}"
CA_CERT_FILE="${CA_CERT_FILE:-$SECRETS_DIR/ca.crt}"
VAULT_AUTO_UNSEAL="${VAULT_AUTO_UNSEAL:-false}"
VAULT_DEV_AUTO_UNSEAL="${VAULT_DEV_AUTO_UNSEAL:-false}"

. "$(dirname "$0")/_lib.sh"

VAULT_FQDN="vault-0.vault.${NAMESPACE}.svc.cluster.local"

vault_cmd() {
  $KUBECTL exec vault-0 -n "$NAMESPACE" -c vault -- sh -c "
    VAULT_ADDR=https://${VAULT_FQDN}:8200 \
    VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
    VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
    $1 2>/dev/null
  "
}

vault_status() {
  $KUBECTL exec "$1" -n "$NAMESPACE" -c vault -- sh -c "
    VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
    VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
    vault status -format=json 2>/dev/null
  " 2>/dev/null || true
}

# --- Wait for Vault ---
echo "Waiting for vault-0..."
pod_is_running() {
  $KUBECTL get pod vault-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running
}
wait_for 120 5 pod_is_running || {
  echo "ERROR: vault-0 pod never reached Running state." >&2
  exit 1
}
sleep 5

echo "Waiting for Vault API to be available..."
for _attempt in $(seq 1 24); do
  status_json=$(vault_status vault-0)
  if printf '%s' "$status_json" | jq -e 'has("initialized")' > /dev/null 2>&1; then
    break
  fi
  echo "  not ready, retrying in 5s..."
  sleep 5
done
if ! printf '%s' "$status_json" | jq -e 'has("initialized")' > /dev/null 2>&1; then
  echo "ERROR: Vault API never became available." >&2
  exit 1
fi
echo "Vault is available."

# --- Initialize Vault ---
is_init=$(printf '%s' "$status_json" | jq -r '.initialized')

if [ "$is_init" = "false" ]; then
  if [ "$VAULT_AUTO_UNSEAL" = "true" ]; then
    echo "Initializing Vault with auto-unseal (1 recovery share, 1 threshold)..."
    INIT_JSON=$($KUBECTL exec vault-0 -n "$NAMESPACE" -c vault -- sh -c "
      VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
      VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
      vault operator init -recovery-shares=1 -recovery-threshold=1 -format=json 2>/dev/null
    ")

    VAULT_ROOT_TOKEN=$(printf '%s' "$INIT_JSON" | jq -r '.root_token')
    RECOVERY_KEY=$(printf '%s' "$INIT_JSON" | jq -r '.recovery_keys_b64[0]')

    mkdir -p "$SECRETS_DIR"
    printf '%s' "$VAULT_ROOT_TOKEN" > "$SECRETS_DIR/vault-bootstrap-token"
    printf '%s' "$RECOVERY_KEY" > "$SECRETS_DIR/vault-recovery-key"
    chmod 600 "$SECRETS_DIR/vault-bootstrap-token" "$SECRETS_DIR/vault-recovery-key"
    echo "Vault initialized with auto-unseal. Credentials saved to $SECRETS_DIR/"
  else
    echo "Initializing Vault (1 key share, 1 threshold)..."
    INIT_JSON=$($KUBECTL exec vault-0 -n "$NAMESPACE" -c vault -- sh -c "
      VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
      VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
      vault operator init -key-shares=1 -key-threshold=1 -format=json 2>/dev/null
    ")

    VAULT_ROOT_TOKEN=$(printf '%s' "$INIT_JSON" | jq -r '.root_token')
    UNSEAL_KEY=$(printf '%s' "$INIT_JSON" | jq -r '.unseal_keys_b64[0]')

    mkdir -p "$SECRETS_DIR"
    printf '%s' "$VAULT_ROOT_TOKEN" > "$SECRETS_DIR/vault-bootstrap-token"
    printf '%s' "$UNSEAL_KEY" > "$SECRETS_DIR/vault-unseal-key"
    chmod 600 "$SECRETS_DIR/vault-bootstrap-token" "$SECRETS_DIR/vault-unseal-key"
    echo "Vault initialized. Credentials saved to $SECRETS_DIR/"
  fi
elif [ "$VAULT_AUTO_UNSEAL" = "true" ]; then
  # Auto-unseal: only need the root token
  if [ -f "$SECRETS_DIR/vault-bootstrap-token" ]; then
    VAULT_ROOT_TOKEN=$(cat "$SECRETS_DIR/vault-bootstrap-token")
    echo "Vault already initialized (auto-unseal), using existing root token."
  else
    echo "Vault already initialized but root token missing." >&2
    echo "  Missing: $SECRETS_DIR/vault-bootstrap-token" >&2
    exit 1
  fi
elif [ -f "$SECRETS_DIR/vault-bootstrap-token" ] && [ -f "$SECRETS_DIR/vault-unseal-key" ]; then
  VAULT_ROOT_TOKEN=$(cat "$SECRETS_DIR/vault-bootstrap-token")
  UNSEAL_KEY=$(cat "$SECRETS_DIR/vault-unseal-key")
  echo "Vault already initialized, using existing credentials. Verifying unseal key..."
  # Try to unseal vault-0 to verify the key works (if it's already unsealed, this is a no-op check)
  unseal_test=$($KUBECTL exec vault-0 -n "$NAMESPACE" -c vault -- sh -c "
    VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
    VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
    vault operator unseal -format=json '$UNSEAL_KEY' 2>&1
  " 2>/dev/null) || true
  if printf '%s' "$unseal_test" | grep -q "invalid unseal key\|invalid barrier\|Unseal Key is not"; then
    echo "ERROR: Saved unseal key does NOT match this vault instance (stale from destroyed cluster?)." >&2
    echo "This vault was initialized by another process. The saved credentials at $SECRETS_DIR/ are stale." >&2
    echo "If this is a fresh cluster, delete $SECRETS_DIR/vault-bootstrap-token and vault-unseal-key, then re-run." >&2
    exit 1
  fi
  echo "Credentials verified OK."
else
  echo "Vault already initialized but local credentials missing or incomplete." >&2
  echo "Need both vault-bootstrap-token and vault-unseal-key in $SECRETS_DIR/" >&2
  if [ ! -f "$SECRETS_DIR/vault-unseal-key" ]; then
    echo "  Missing: vault-unseal-key" >&2
  fi
  if [ ! -f "$SECRETS_DIR/vault-bootstrap-token" ]; then
    echo "  Missing: vault-bootstrap-token" >&2
  fi
  exit 1
fi

# --- Dev auto-unseal: store unseal key in K8s secret ---
if [ "$VAULT_DEV_AUTO_UNSEAL" = "true" ] && [ -n "$UNSEAL_KEY" ]; then
  echo "Storing unseal key in K8s secret (dev auto-unseal)..."
  $KUBECTL create secret generic vault-unseal-key \
    -n "$NAMESPACE" \
    --from-literal=key="$UNSEAL_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
fi

# --- Unseal all Vault pods ---
if [ "$VAULT_AUTO_UNSEAL" = "true" ]; then
  echo "Auto-unseal enabled, waiting for KMS to unseal pods..."
  for i in $(seq 0 $((VAULT_REPLICAS - 1))); do
    for _s in $(seq 1 20); do
      seal_json=$(vault_status "vault-$i")
      is_sealed=$(printf '%s' "$seal_json" | jq -r '.sealed' 2>/dev/null || echo "")
      if [ "$is_sealed" = "false" ]; then
        echo "  vault-$i unsealed via KMS."
        break
      fi
      sleep 3
    done
    if [ "$is_sealed" != "false" ]; then
      echo "  WARNING: vault-$i not unsealed after 60s (sealed=$is_sealed)." >&2
    fi
  done
else
  echo "Unsealing Vault pods..."
  for i in $(seq 0 $((VAULT_REPLICAS - 1))); do
    seal_json=""
    for _s in $(seq 1 5); do
      seal_json=$(vault_status "vault-$i")
      if printf '%s' "$seal_json" | jq -e '.sealed' > /dev/null 2>&1; then
        break
      fi
      sleep 3
    done
    is_sealed=$(printf '%s' "$seal_json" | jq -r '.sealed' 2>/dev/null || echo "")

    if [ "$is_sealed" = "true" ]; then
      echo "  Unsealing vault-$i..."
      retry 3 5 $KUBECTL exec "vault-$i" -n "$NAMESPACE" -c vault -- sh -c "
        VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
        VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
        vault operator unseal '$UNSEAL_KEY'
      " > /dev/null 2>&1
      # Verify unseal succeeded
      verify_json=$(vault_status "vault-$i")
      verify_sealed=$(printf '%s' "$verify_json" | jq -r '.sealed' 2>/dev/null || echo "unknown")
      if [ "$verify_sealed" = "false" ]; then
        echo "  vault-$i unsealed."
      else
        echo "  WARNING: vault-$i may still be sealed (sealed=$verify_sealed)." >&2
      fi
    elif [ "$is_sealed" = "false" ]; then
      echo "  vault-$i already unsealed."
    else
      echo "  vault-$i not reachable, skipping."
    fi
  done
fi

# Wait for vault to become active
echo "Waiting for Vault to become active..."
_vault_active=false
for _attempt in $(seq 1 30); do
  health_json=$(vault_status vault-0)
  is_init=$(printf '%s' "$health_json" | jq -r '.initialized' 2>/dev/null || echo "")
  is_sealed=$(printf '%s' "$health_json" | jq -r '.sealed' 2>/dev/null || echo "")
  if [ "$is_init" = "true" ] && [ "$is_sealed" = "false" ]; then
    _vault_active=true
    echo "Vault is active."
    break
  fi
  sleep 2
done
if [ "$_vault_active" != "true" ]; then
  echo "ERROR: Vault did not become active within 60 seconds." >&2
  exit 1
fi

# --- Enable Kubernetes auth ---
echo "Enabling Kubernetes auth backend..."
vault_cmd "vault auth enable kubernetes" > /dev/null 2>&1 || echo "  Already enabled."

echo "Configuring Kubernetes auth backend..."
vault_cmd "vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc.cluster.local" > /dev/null

echo "Creating default-default role..."
vault_cmd "vault write auth/kubernetes/role/default-default \
  bound_service_account_names=default \
  bound_service_account_namespaces=default \
  policies=default \
  ttl=21600 max_ttl=21600 period=21600" > /dev/null

# --- Mount cabotage-secrets KV ---
echo "Mounting cabotage-secrets KV..."
vault_cmd "vault secrets enable -path=cabotage-secrets kv" > /dev/null 2>&1 || echo "  Already mounted."

# --- Mount cabotage-consul secrets engine ---
echo "Mounting cabotage-consul secrets engine..."
vault_cmd "vault secrets enable -path=cabotage-consul consul" > /dev/null 2>&1 || echo "  Already mounted."

echo "Configuring Consul secrets backend..."
CONSUL_MGMT_TOKEN=$(cat "$SECRETS_DIR/consul-bootstrap-token")

echo "  Creating Consul management token for Vault..."
consul_response=$($KUBECTL exec consul-0 -n "$NAMESPACE" -c consul -- sh -c "
  CONSUL_HTTP_TOKEN='$CONSUL_MGMT_TOKEN' consul acl token create \
    -description='Vault Consul Backend Management Token' \
    -policy-name=global-management \
    -format=json
")
VAULT_CONSUL_MGMT=$(printf '%s' "$consul_response" | jq -r '.SecretID')

vault_cmd "vault write cabotage-consul/config/access address=127.0.0.1:8500 scheme=http token=$VAULT_CONSUL_MGMT" > /dev/null

echo "Configuring readonly role for Consul secrets backend..."
READONLY_POLICY=$(printf '%s' 'key "cabotage/global" { policy = "read" }
key "vault/" { policy = "deny" }
node "" { policy = "read" }
service "" { policy = "read" }' | base64 | tr -d '\n')
vault_cmd "vault write cabotage-consul/roles/readonly token_type=client lease=1h policy=$READONLY_POLICY" > /dev/null

# --- Mount cabotage-ca PKI ---
echo "Mounting cabotage-ca PKI backend..."
vault_cmd "vault secrets enable -path=cabotage-ca pki" > /dev/null 2>&1 || echo "  Already mounted."

# Check if CA is already signed
ca_check=$(vault_cmd "vault read -field=certificate cabotage-ca/cert/ca" 2>/dev/null || echo "")
if printf '%s' "$ca_check" | grep -q "BEGIN CERTIFICATE"; then
  echo "  Internal CA already signed."
else
  echo "  Configuring CA URLs..."
  vault_cmd "vault write cabotage-ca/config/urls \
    issuing_certificates=https://vault.cabotage.svc.cluster.local/v1/cabotage-ca/ca \
    crl_distribution_points=https://vault.cabotage.svc.cluster.local/v1/cabotage-ca/crl" > /dev/null

  vault_cmd "vault write cabotage-ca/config/auto-tidy \
    enabled=true tidy_cert_store=true tidy_revoked_certs=true \
    tidy_revoked_cert_issuer_associations=true" > /dev/null

  echo "  Generating intermediate CA CSR..."
  CSR=$(vault_cmd "vault write -field=csr cabotage-ca/intermediate/generate/internal \
    common_name='Kubernetes Internal Intermediate CA' \
    ttl=43800h key_type=rsa key_bits=4096 \
    exclude_cn_from_sans=true")

  echo "  Signing CSR with root CA..."
  TMPDIR=$(mktemp -d)
  printf '%s' "$CSR" > "$TMPDIR/vault-intermediate.csr"

  cat > "$TMPDIR/ext.cnf" <<EXTEOF
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, keyCertSign, cRLSign
EXTEOF

  openssl x509 -req -in "$TMPDIR/vault-intermediate.csr" \
    -CA "$CA_CERT_FILE" -CAkey "$SECRETS_DIR/ca.key" -CAcreateserial \
    -out "$TMPDIR/vault-intermediate.crt" -days 1825 \
    -extfile "$TMPDIR/ext.cnf" 2>/dev/null

  SIGNED_CERT=$(cat "$TMPDIR/vault-intermediate.crt")
  rm -rf "$TMPDIR"

  echo "  Providing signed certificate back to Vault..."
  printf '%s' "$SIGNED_CERT" | $KUBECTL exec -i vault-0 -n "$NAMESPACE" -c vault -- sh -c "
    VAULT_ADDR=https://\$HOSTNAME.vault.$NAMESPACE.svc.cluster.local:8200 \
    VAULT_CACERT=/var/run/secrets/cabotage.io/ca.crt \
    VAULT_TOKEN='$VAULT_ROOT_TOKEN' \
    vault write cabotage-ca/intermediate/set-signed certificate=-
  "

  echo "  Internal CA configured."
fi

echo "Vault bootstrap complete!"
