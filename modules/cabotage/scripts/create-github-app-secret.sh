#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

if ! secret_exists "github-app-private-key.pem" || ! secret_exists "github-webhook-secret"; then
  echo "GitHub App secrets not found, skipping."
  exit 0
fi

PRIVATE_KEY_B64=$(secret_read "github-app-private-key.pem" | base64 | tr -d '\n')
WEBHOOK_SECRET=$(secret_read "github-webhook-secret" | tr -d '[:space:]')

CLIENT_ID_ARG=""
if secret_exists "github-app-client-id"; then
  CLIENT_ID=$(secret_read "github-app-client-id" | tr -d '[:space:]')
  CLIENT_ID_ARG="--from-literal=client-id=$CLIENT_ID"
fi

CLIENT_SECRET_ARG=""
if secret_exists "github-app-client-secret"; then
  CLIENT_SECRET=$(secret_read "github-app-client-secret" | tr -d '[:space:]')
  CLIENT_SECRET_ARG="--from-literal=client-secret=$CLIENT_SECRET"
fi

$KUBECTL create secret generic cabotage-github-app \
  --namespace "$NAMESPACE" \
  --from-literal=app-id="$GITHUB_APP_ID" \
  --from-literal=private-key="$PRIVATE_KEY_B64" \
  --from-literal=webhook-secret="$WEBHOOK_SECRET" \
  $CLIENT_ID_ARG \
  $CLIENT_SECRET_ARG \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "GitHub App secret created/updated."
