#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"

ACCESS_KEY=$(kubectl get secret rustfs-admin -n "$NAMESPACE" -o jsonpath='{.data.RUSTFS_ACCESS_KEY}' | base64 -d)
SECRET_KEY=$(kubectl get secret rustfs-admin -n "$NAMESPACE" -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 -d)

kubectl create secret generic resident-monitoring-s3 \
  --namespace "$NAMESPACE" \
  --from-literal=access-key-id="$ACCESS_KEY" \
  --from-literal=secret-key="$SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "resident-monitoring-s3 secret created."
