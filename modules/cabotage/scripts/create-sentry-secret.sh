#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

if ! secret_exists "sentry-dsn"; then
  echo "Sentry DSN not found, skipping."
  exit 0
fi

DSN=$(secret_read "sentry-dsn" | tr -d '[:space:]')

$KUBECTL create secret generic cabotage-sentry \
  --namespace "$NAMESPACE" \
  --from-literal=dsn="$DSN" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Sentry secret created/updated."
