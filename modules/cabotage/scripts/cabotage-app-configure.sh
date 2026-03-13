#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
. "$(dirname "$0")/_lib.sh"

# --- Build DB URI ---
echo "Fetching postgres credentials..."
DB_USERNAME=$($KUBECTL get -n postgres secret cabotage-app -o jsonpath='{.data.username}' | base64 -d)
DB_PASSWORD=$($KUBECTL get -n postgres secret cabotage-app -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Failed: postgres secret cabotage-app not found or missing username/password in namespace postgres"
  exit 1
fi
DB_URI="postgresql://${DB_USERNAME}:${DB_PASSWORD}@cabotage-rw.postgres.svc.cluster.local:5432/app?sslmode=verify-full&sslrootcert=/var/run/secrets/cabotage.io/ca.crt"

# --- Build Redis URI ---
echo "Fetching redis credentials..."
REDIS_PASSWORD=$($KUBECTL get -n redis secret cabotage-password -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$REDIS_PASSWORD" ]; then
  echo "Failed: redis secret cabotage-password not found or missing password in namespace redis"
  exit 1
fi
REDIS_URI="rediss://:${REDIS_PASSWORD}@cabotage.redis.svc.cluster.local:6379/0?ssl_ca_certs=/var/run/secrets/cabotage.io/ca.crt&ssl_cert_reqs=required"

# --- Generate app secrets ---
SECRET_KEY=$(openssl rand -base64 48)
PASSWORD_SALT=$(openssl rand -base64 48)
REGISTRY_AUTH_SECRET=$(openssl rand -base64 32)

# --- Create cabotage-app-secrets ---
echo "Creating cabotage-app-secrets..."
$KUBECTL create secret generic cabotage-app-secrets \
  --namespace "$NAMESPACE" \
  --from-literal=database-uri="$DB_URI" \
  --from-literal=redis-uri="$REDIS_URI" \
  --from-literal=secret-key="$SECRET_KEY" \
  --from-literal=password-salt="$PASSWORD_SALT" \
  --from-literal=registry-auth-secret="$REGISTRY_AUTH_SECRET" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

# --- Restart deployments to pick up secrets ---
echo "Restarting cabotage-app deployments..."
$KUBECTL rollout restart -n "$NAMESPACE" deployment/cabotage-app-web

echo "Waiting for cabotage-app-web rollout..."
$KUBECTL rollout status -n "$NAMESPACE" deployment/cabotage-app-web --timeout=300s

# --- Run DB migrations ---
echo "Running database migrations..."
retry 3 10 $KUBECTL exec -n "$NAMESPACE" deployment/cabotage-app-web -c cabotage-app -- \
  python -m flask db upgrade head

echo "Cabotage app configuration complete!"
