#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/_lib.sh"

ACCESS_KEY=$(openssl rand -hex 10 | tr 'a-f' 'A-F' | tr '0-9' 'A-J')
SECRET_KEY=$(openssl rand -hex 20 | tr 'a-f' 'A-F' | tr '0-9' 'A-J')

echo "Creating secret rustfs-admin in namespace cabotage"
echo "  RUSTFS_ACCESS_KEY=${ACCESS_KEY}"
echo "  RUSTFS_SECRET_KEY=${SECRET_KEY}"

$KUBECTL create secret generic rustfs-admin \
  --namespace cabotage \
  --from-literal=RUSTFS_ACCESS_KEY="${ACCESS_KEY}" \
  --from-literal=RUSTFS_SECRET_KEY="${SECRET_KEY}" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Done."
