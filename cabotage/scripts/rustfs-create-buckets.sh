#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"

echo "Waiting for RustFS to be ready..."
kubectl rollout status statefulset/rustfs -n "$NAMESPACE" --timeout=300s

for bucket in cabotage-registry resident-loki resident-mimir; do
  echo "Creating bucket: $bucket"
  kubectl run rustfs-create-bucket -n "$NAMESPACE" --rm -i --restart=Never \
    --image=minio/mc \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "rustfs-create-bucket",
          "image": "minio/mc",
          "command": ["sh", "-c", "mc alias set rustfs https://rustfs.'"$NAMESPACE"'.svc.cluster.local:9000 $RUSTFS_ACCESS_KEY $RUSTFS_SECRET_KEY --insecure && mc mb --ignore-existing rustfs/'"$bucket"' --insecure"],
          "env": [
            {"name": "RUSTFS_ACCESS_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_ACCESS_KEY"}}},
            {"name": "RUSTFS_SECRET_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_SECRET_KEY"}}}
          ]
        }]
      }
    }'
done

echo "Buckets created."
