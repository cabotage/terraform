#!/bin/sh
set -e

CONSUL_HTTP="http://localhost:8500"
VAULT_ADDR="https://vault-0.vault.cabotage.svc.cluster.local:8200"
VAULT_CACERT="/var/run/secrets/cabotage.io/ca.crt"
KUBE_API="https://kubernetes.default.svc"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBE_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE="cabotage"

vault_api() {
  local method=$1 path=$2 data=$3
  if [ -n "$data" ]; then
    curl -sf --cacert "$VAULT_CACERT" \
      -H "X-Vault-Token: $VAULT_ROOT_TOKEN" \
      -X "$method" -d "$data" \
      "$VAULT_ADDR/v1/$path"
  else
    curl -sf --cacert "$VAULT_CACERT" \
      -H "X-Vault-Token: $VAULT_ROOT_TOKEN" \
      -X "$method" \
      "$VAULT_ADDR/v1/$path"
  fi
}

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

# ============================
# Wait for Vault to be running
# ============================
echo "Waiting for Vault to be available..."
until curl -sk "$VAULT_ADDR/v1/sys/seal-status" > /dev/null 2>&1; do
  echo "  not ready, retrying in 5s..."
  sleep 5
done
echo "Vault is available."

# ============================
# Initialize Vault
# ============================
stored=$(kube_get_secret vault-root-token | \
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
stored_decoded=$(printf '%s' "$stored" | base64 -d 2>/dev/null || echo "null")

init_status=$(curl -sf --cacert "$VAULT_CACERT" "$VAULT_ADDR/v1/sys/init")
is_init=$(printf '%s' "$init_status" | sed -n 's/.*"initialized"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')

if [ "$is_init" = "false" ]; then
  echo "Initializing Vault (1 key share, 1 threshold)..."
  init_response=$(curl -sf --cacert "$VAULT_CACERT" \
    -X PUT -d '{"secret_shares": 1, "secret_threshold": 1}' \
    "$VAULT_ADDR/v1/sys/init")

  VAULT_ROOT_TOKEN=$(printf '%s' "$init_response" | sed -n 's/.*"root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  UNSEAL_KEY=$(printf '%s' "$init_response" | sed -n 's/.*"keys"[[:space:]]*:[[:space:]]*\["\([^"]*\)".*/\1/p')

  echo "Vault initialized. Storing root token and unseal key..."
  kube_patch_secret vault-root-token token "$VAULT_ROOT_TOKEN" > /dev/null
  kube_patch_secret vault-unseal-key key "$UNSEAL_KEY" > /dev/null
elif [ "$stored_decoded" != "null" ] && [ -n "$stored_decoded" ]; then
  echo "Vault already initialized. Using stored root token."
  VAULT_ROOT_TOKEN="$stored_decoded"

  # Retrieve unseal key
  stored_key=$(kube_get_secret vault-unseal-key | \
    sed -n 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  UNSEAL_KEY=$(printf '%s' "$stored_key" | base64 -d 2>/dev/null || echo "")
else
  echo "Vault already initialized but no root token found in secret."
  echo "Store the root token in vault-root-token secret and re-run."
  exit 1
fi

# ============================
# Unseal all Vault pods
# ============================
echo "Unsealing Vault pods..."
for i in 0 1 2; do
  pod_addr="https://vault-$i.vault.cabotage.svc.cluster.local:8200"
  seal_status=$(curl -sf --cacert "$VAULT_CACERT" "$pod_addr/v1/sys/seal-status" 2>/dev/null || echo '{}')
  is_sealed=$(printf '%s' "$seal_status" | sed -n 's/.*"sealed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')

  if [ "$is_sealed" = "true" ]; then
    echo "  Unsealing vault-$i..."
    curl -sf --cacert "$VAULT_CACERT" \
      -X PUT -d "{\"key\": \"$UNSEAL_KEY\"}" \
      "$pod_addr/v1/sys/unseal" > /dev/null
    echo "  vault-$i unsealed."
  elif [ -n "$is_sealed" ]; then
    echo "  vault-$i already unsealed."
  else
    echo "  vault-$i not reachable, skipping."
  fi
done

# Wait for vault to become active after unseal
echo "Waiting for Vault to become active..."
for i in $(seq 1 30); do
  health=$(curl -sf --cacert "$VAULT_CACERT" "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{}')
  is_init=$(printf '%s' "$health" | sed -n 's/.*"initialized"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
  is_sealed=$(printf '%s' "$health" | sed -n 's/.*"sealed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
  if [ "$is_init" = "true" ] && [ "$is_sealed" = "false" ]; then
    echo "Vault is active."
    break
  fi
  sleep 2
done

# ============================
# Enable Kubernetes auth
# ============================
echo "Enabling Kubernetes auth backend..."
auth_list=$(vault_api GET sys/auth 2>/dev/null || echo '{}')
if printf '%s' "$auth_list" | grep -q '"kubernetes/"'; then
  echo "  Kubernetes auth already enabled."
else
  vault_api POST sys/auth/kubernetes '{"type":"kubernetes","description":"login for kubernetes pods via ServiceAccount JWT"}' > /dev/null
  echo "  Enabled."
fi

echo "Configuring Kubernetes auth backend..."
vault_api POST auth/kubernetes/config '{"kubernetes_host":"https://kubernetes.default.svc.cluster.local"}' > /dev/null

echo "Creating default-default role..."
vault_api POST auth/kubernetes/role/default-default '{
  "bound_service_account_names":["default"],
  "bound_service_account_namespaces":["default"],
  "policies":["default"],
  "ttl":"21600","max_ttl":"21600","period":"21600"
}' > /dev/null

# ============================
# Mount cabotage-secrets KV
# ============================
echo "Mounting cabotage-secrets KV..."
mounts=$(vault_api GET sys/mounts 2>/dev/null || echo '{}')
if printf '%s' "$mounts" | grep -q '"cabotage-secrets/"'; then
  echo "  Already mounted."
else
  vault_api POST sys/mounts/cabotage-secrets '{"type":"kv","description":"secret storage for cabotage"}' > /dev/null
  echo "  Mounted."
fi

# ============================
# Mount cabotage-consul secrets engine
# ============================
echo "Mounting cabotage-consul secrets engine..."
if printf '%s' "$mounts" | grep -q '"cabotage-consul/"'; then
  echo "  Already mounted."
else
  vault_api POST sys/mounts/cabotage-consul '{"type":"consul","description":"automate consul tokens for kubernetes pods via ServiceAccount JWT"}' > /dev/null
  echo "  Mounted."

  # Get consul management token
  consul_mgmt=$(kube_get_secret consul-management-token | \
    sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  consul_mgmt_decoded=$(printf '%s' "$consul_mgmt" | base64 -d 2>/dev/null || echo "")

  # Create a consul management token for vault
  echo "  Creating Consul management token for Vault..."
  token_response=$(curl -sf \
    -H "X-Consul-Token: $consul_mgmt_decoded" \
    -X PUT -d '{"Description":"Vault Consul Backend Management Token","Policies":[{"Name":"global-management"}],"Local":true}' \
    "http://consul-0.consul.cabotage.svc.cluster.local:8500/v1/acl/token")
  vault_consul_mgmt=$(printf '%s' "$token_response" | sed -n 's/.*"SecretID"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  echo "  Configuring Consul secrets backend..."
  vault_api POST cabotage-consul/config/access "{\"address\":\"127.0.0.1:8500\",\"scheme\":\"http\",\"token\":\"$vault_consul_mgmt\"}" > /dev/null
fi

# Configure readonly role
echo "Configuring readonly role for Consul secrets backend..."
READONLY_POLICY=$(printf '%s' 'key "cabotage/global" { policy = "read" }
key "vault/" { policy = "deny" }
node "" { policy = "read" }
service "" { policy = "read" }' | base64)
vault_api POST cabotage-consul/roles/readonly "{\"token_type\":\"client\",\"lease\":\"1h\",\"policy\":\"$READONLY_POLICY\"}" > /dev/null

# ============================
# Mount cabotage-ca PKI
# ============================
echo "Mounting cabotage-ca PKI backend..."
if printf '%s' "$mounts" | grep -q '"cabotage-ca/"'; then
  echo "  Already mounted."
else
  vault_api POST sys/mounts/cabotage-ca '{"type":"pki","description":"Kubernetes Internal Intermediate CA"}' > /dev/null
  echo "  Mounted."
fi

# Check if CA is already signed
ca_check=$(vault_api GET cabotage-ca/cert/ca 2>/dev/null || echo '{}')
if printf '%s' "$ca_check" | grep -q '"certificate"'; then
  echo "  Internal CA already signed."
else
  echo "  Configuring CA URLs..."
  vault_api POST cabotage-ca/config/urls '{
    "issuing_certificates":"https://vault.cabotage.svc.cluster.local/v1/cabotage-ca/ca",
    "crl_distribution_points":"https://vault.cabotage.svc.cluster.local/v1/cabotage-ca/crl"
  }' > /dev/null

  vault_api POST cabotage-ca/config/auto-tidy '{
    "enabled":true,"tidy_cert_store":true,"tidy_revoked_certs":true,"tidy_revoked_cert_issuer_associations":true
  }' > /dev/null

  echo "  Generating intermediate CA CSR..."
  csr_response=$(vault_api POST cabotage-ca/intermediate/generate/internal '{
    "common_name":"Kubernetes Internal Intermediate CA",
    "ttl":"43800h","key_type":"rsa","key_bits":4096,
    "exclude_cn_from_sans":true
  }')
  CSR=$(printf '%s' "$csr_response" | sed -n 's/.*"csr"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  # Get root CA key+cert from cert-manager secret
  echo "  Retrieving root CA for signing..."
  root_ca_secret=$(curl -s --cacert "$KUBE_CA" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    "$KUBE_API/api/v1/namespaces/cert-manager/secrets/cabotage-root-ca-key-pair")

  CA_CRT_B64=$(printf '%s' "$root_ca_secret" | sed -n 's/.*"tls.crt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  CA_KEY_B64=$(printf '%s' "$root_ca_secret" | sed -n 's/.*"tls.key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  CA_CRT=$(printf '%s' "$CA_CRT_B64" | base64 -d)
  CA_KEY=$(printf '%s' "$CA_KEY_B64" | base64 -d)

  # Write CSR, CA cert, CA key to temp files and sign with openssl
  echo "  Signing intermediate CA with root CA..."
  printf '%b' "$CSR" > /tmp/intermediate.csr
  printf '%s' "$CA_CRT" > /tmp/ca.crt
  printf '%s' "$CA_KEY" > /tmp/ca.key

  # Create openssl config for intermediate CA
  cat > /tmp/intermediate.cnf <<SSLEOF
[v3_intermediate_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
SSLEOF

  openssl x509 -req -in /tmp/intermediate.csr \
    -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial \
    -days 1825 -sha256 \
    -extfile /tmp/intermediate.cnf -extensions v3_intermediate_ca \
    -out /tmp/intermediate.crt 2>/dev/null

  SIGNED_CERT=$(cat /tmp/intermediate.crt)

  # Clean up sensitive files
  rm -f /tmp/ca.key /tmp/intermediate.csr /tmp/ca.crt /tmp/ca.srl /tmp/intermediate.cnf

  # Escape cert for JSON
  SIGNED_CERT_JSON=$(printf '%s' "$SIGNED_CERT" | sed ':a;N;$!ba;s/\n/\\n/g')

  echo "  Providing signed certificate back to Vault..."
  vault_api POST cabotage-ca/intermediate/set-signed "{\"certificate\":\"$SIGNED_CERT_JSON\"}" > /dev/null

  rm -f /tmp/intermediate.crt
  echo "  Internal CA configured."
fi

echo "Vault bootstrap complete!"
