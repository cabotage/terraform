#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
. "$(dirname "$0")/_lib.sh"

# --- Create registry-secrets (http secret) ---
echo "Creating registry-secrets..."
HTTP_SECRET=$(openssl rand -base64 32)
$KUBECTL create secret generic registry-secrets \
  --namespace "$NAMESPACE" \
  --from-literal=http-secret="$HTTP_SECRET" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

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

# --- Create signing cert secret ---
echo "Creating registry-signing-cert secret..."
$KUBECTL create secret generic registry-signing-cert \
  --namespace "$NAMESPACE" \
  --from-literal=public_key_bundle="$SIGNING_CERT" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

# --- Restart registry ---
echo "Restarting registry deployment..."
$KUBECTL rollout restart -n "$NAMESPACE" deployment/registry

echo "Waiting for registry rollout..."
$KUBECTL rollout status -n "$NAMESPACE" deployment/registry --timeout=300s

echo "Registry configuration complete!"
