#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

ARGS=""
if secret_exists "slack-client-id"; then
  ARGS="$ARGS --from-literal=client-id=$(secret_read "slack-client-id" | tr -d '[:space:]')"
fi
if secret_exists "slack-client-secret"; then
  ARGS="$ARGS --from-literal=client-secret=$(secret_read "slack-client-secret" | tr -d '[:space:]')"
fi

if [ -z "$ARGS" ]; then
  echo "Slack notification secrets not found, skipping."
  exit 0
fi

$KUBECTL create secret generic cabotage-notifications-slack \
  --namespace "$NAMESPACE" \
  $ARGS \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Slack notification secret created/updated."
