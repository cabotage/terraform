#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

# Generate root CA locally if not present, distribute cert via ConfigMaps.
# Root CA key never enters K8s.

CA_CERT_FILE="${CA_CERT_FILE:-$SECRETS_DIR/ca.crt}"

if [ ! -f "$CA_CERT_FILE" ] || ! secret_exists "ca.key"; then
  echo "Generating root CA..."
  TMPDIR=$(mktemp -d)
  trap "rm -rf '$TMPDIR'" EXIT
  openssl ecparam -genkey -name prime256v1 -noout -out "$TMPDIR/ca.key" 2>/dev/null
  CLUSTER_SHORT=$(printf '%s' "$CLUSTER_ID" | sed 's|.*/||')
  cat > "$TMPDIR/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = ${CLUSTER_SHORT} Cabotage Root CA
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
EOF
  openssl req -new -x509 -key "$TMPDIR/ca.key" -out "$CA_CERT_FILE" \
    -days 3650 -config "$TMPDIR/openssl.cnf"
  secret_write_from_file "ca.key" "$TMPDIR/ca.key"
  rm -rf "$TMPDIR"
  echo "Root CA key stored."
  echo "Root CA cert saved to $CA_CERT_FILE"
else
  echo "Using existing root CA."
fi

CA_CRT=$(cat "$CA_CERT_FILE")
for ns in cabotage default; do
  $KUBECTL create configmap cabotage-ca -n "$ns" \
    --from-literal="ca.crt=$CA_CRT" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
done
echo "Root CA cert distributed to configmaps."
