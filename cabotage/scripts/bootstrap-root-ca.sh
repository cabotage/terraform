#!/bin/sh
set -e

# Generate root CA locally if not present, distribute cert via ConfigMaps.
# Root CA key never enters K8s.

if [ ! -f "$SECRETS_DIR/ca.crt" ] || [ ! -f "$SECRETS_DIR/ca.key" ]; then
  echo "Generating root CA..."
  mkdir -p "$SECRETS_DIR"
  openssl ecparam -genkey -name prime256v1 -noout -out "$SECRETS_DIR/ca.key" 2>/dev/null
  openssl req -new -x509 -key "$SECRETS_DIR/ca.key" -out "$SECRETS_DIR/ca.crt" \
    -days 3650 -subj "/CN=$CLUSTER_ID Cabotage Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
  chmod 600 "$SECRETS_DIR/ca.key"
  echo "Root CA saved to $SECRETS_DIR/ca.{crt,key}"
else
  echo "Using existing root CA from $SECRETS_DIR/"
fi

CA_CRT=$(cat "$SECRETS_DIR/ca.crt")
for ns in cabotage default; do
  kubectl create configmap cabotage-ca -n "$ns" \
    --from-literal="ca.crt=$CA_CRT" \
    --dry-run=client -o yaml | kubectl apply -f -
done
echo "Root CA cert distributed to configmaps."
