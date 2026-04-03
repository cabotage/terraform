#!/bin/sh
set -e

. "$(dirname "$0")/_lib.sh"

if ! secret_exists "dockerhub-username" || ! secret_exists "dockerhub-token"; then
  echo "DockerHub secrets not found, skipping."
  exit 0
fi

USERNAME=$(secret_read "dockerhub-username" | tr -d '[:space:]')
TOKEN=$(secret_read "dockerhub-token" | tr -d '[:space:]')

$KUBECTL create secret generic cabotage-dockerhub \
  --namespace "$NAMESPACE" \
  --from-literal=username="$USERNAME" \
  --from-literal=token="$TOKEN" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "DockerHub secret created/updated."
