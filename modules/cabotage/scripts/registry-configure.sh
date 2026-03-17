#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
. "$(dirname "$0")/_lib.sh"

# --- Configure registry-secrets ---
echo "Configuring registry-secrets..."
ensure_secret "registry-secrets" "$NAMESPACE"
ensure_secret_key "registry-secrets" "$NAMESPACE" "http-secret" "openssl rand -base64 32"

# --- Fetch signing cert from cabotage-app ---
echo "Fetching Docker signing cert from cabotage-app..."
SIGNING_CERT=$(
  retry 10 5 $KUBECTL -n "$NAMESPACE" exec statefulset/consul -c consul -- \
    curl --silent --fail --cacert /var/run/secrets/cabotage.io/ca.crt \
    https://cabotage-app.cabotage.svc.cluster.local/signing-cert?raw=true
)
if [ -z "$SIGNING_CERT" ]; then
  echo "Failed: signing cert is empty after retries"
  exit 1
fi

# --- Fetch signing JWKS from cabotage-app ---
echo "Fetching Docker signing JWKS from cabotage-app..."
SIGNING_JWKS=$(
  retry 10 5 $KUBECTL -n "$NAMESPACE" exec statefulset/consul -c consul -- \
    curl --silent --fail --cacert /var/run/secrets/cabotage.io/ca.crt \
    https://cabotage-app.cabotage.svc.cluster.local/signing-jwks
)
if [ -z "$SIGNING_JWKS" ]; then
  echo "Failed: signing JWKS is empty after retries"
  exit 1
fi

# --- Create signing cert secret ---
echo "Creating registry-signing-cert secret..."
$KUBECTL create secret generic registry-signing-cert \
  --namespace "$NAMESPACE" \
  --from-literal=public_key_bundle="$SIGNING_CERT" \
  --from-literal=jwks.json="$SIGNING_JWKS" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

# --- Restart registry ---
echo "Restarting registry deployment..."
$KUBECTL rollout restart -n "$NAMESPACE" deployment/registry

echo "Waiting for registry rollout..."
$KUBECTL rollout status -n "$NAMESPACE" deployment/registry --timeout=300s

echo "Registry configuration complete!"
