#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

ARGS=""
if secret_exists "discord-client-id"; then
  ARGS="$ARGS --from-literal=client-id=$(secret_read "discord-client-id" | tr -d '[:space:]')"
fi
if secret_exists "discord-client-secret"; then
  ARGS="$ARGS --from-literal=client-secret=$(secret_read "discord-client-secret" | tr -d '[:space:]')"
fi
if secret_exists "discord-bot-token"; then
  ARGS="$ARGS --from-literal=bot-token=$(secret_read "discord-bot-token" | tr -d '[:space:]')"
fi

if [ -z "$ARGS" ]; then
  echo "Discord notification secrets not found, skipping."
  exit 0
fi

$KUBECTL create secret generic cabotage-notifications-discord \
  --namespace "$NAMESPACE" \
  $ARGS \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Discord notification secret created/updated."
