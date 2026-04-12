#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/_lib.sh"

ACCESS_KEY=$(openssl rand -hex 10 | tr 'a-f' 'A-F' | tr '0-9' 'A-J')
SECRET_KEY=$(openssl rand -hex 20 | tr 'a-f' 'A-F' | tr '0-9' 'A-J')

echo "Creating secret seaweedfs-admin in namespace cabotage"
echo "  SEAWEEDFS_ACCESS_KEY=${ACCESS_KEY}"
echo "  SEAWEEDFS_SECRET_KEY=${SECRET_KEY}"

$KUBECTL create secret generic seaweedfs-admin \
  --namespace cabotage \
  --from-literal=SEAWEEDFS_ACCESS_KEY="${ACCESS_KEY}" \
  --from-literal=SEAWEEDFS_SECRET_KEY="${SECRET_KEY}" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Done."
