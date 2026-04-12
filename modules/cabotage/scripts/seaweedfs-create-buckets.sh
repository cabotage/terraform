#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
SEAWEEDFS_STANDALONE="${SEAWEEDFS_STANDALONE:-false}"
. "$(dirname "$0")/_lib.sh"

if [ "$SEAWEEDFS_STANDALONE" = "true" ]; then
  echo "Waiting for SeaweedFS standalone to be ready..."
  $KUBECTL rollout status statefulset/seaweedfs-standalone -n "$NAMESPACE" --timeout=300s
  FILER_ADDR="localhost:8888"
  MASTER_ADDR="localhost:9333"
  EXEC_TARGET="seaweedfs-standalone-0"
else
  echo "Waiting for SeaweedFS components to be ready..."
  $KUBECTL rollout status statefulset/seaweedfs-master -n "$NAMESPACE" --timeout=300s
  $KUBECTL rollout status statefulset/seaweedfs-volume -n "$NAMESPACE" --timeout=300s
  $KUBECTL rollout status statefulset/seaweedfs-filer -n "$NAMESPACE" --timeout=300s
  $KUBECTL rollout status statefulset/seaweedfs-s3 -n "$NAMESPACE" --timeout=300s
  FILER_ADDR="seaweedfs-filer.${NAMESPACE}.svc.cluster.local:8888"
  MASTER_ADDR="seaweedfs-master.${NAMESPACE}.svc.cluster.local:9333"
  EXEC_TARGET="seaweedfs-filer-0"
fi

# --- Helper: run weed shell command ---
run_weed_shell() {
  $KUBECTL exec -n "$NAMESPACE" "$EXEC_TARGET" -- \
    sh -c "echo '$1' | weed shell -master=$MASTER_ADDR -filer=$FILER_ADDR"
}

# --- Helper: run weed shell with retry ---
run_weed_shell_retry() {
  attempt=1
  while [ $attempt -le 30 ]; do
    if run_weed_shell "$1"; then
      return 0
    fi
    echo "Attempt $attempt failed, retrying in 5s..."
    attempt=$((attempt + 1))
    sleep 5
  done
  echo "Failed after 30 attempts"
  exit 1
}

# --- Create buckets ---
for bucket in cabotage-registry resident-loki resident-mimir; do
  echo "Creating bucket: $bucket"
  run_weed_shell_retry "s3.bucket.create -name $bucket"
done

# --- Configure admin identity ---
ADMIN_ACCESS_KEY=$($KUBECTL get secret seaweedfs-admin -n "$NAMESPACE" -o jsonpath='{.data.SEAWEEDFS_ACCESS_KEY}' | base64 -d)
ADMIN_SECRET_KEY=$($KUBECTL get secret seaweedfs-admin -n "$NAMESPACE" -o jsonpath='{.data.SEAWEEDFS_SECRET_KEY}' | base64 -d)

echo "Configuring admin S3 identity..."
run_weed_shell "s3.configure -apply -user admin -access_key $ADMIN_ACCESS_KEY -secret_key $ADMIN_SECRET_KEY -actions Admin,Read,Write,List,Tagging"

# --- Create per-service users and configure S3 access ---
for service in resident-loki resident-mimir cabotage-registry; do
  ACCESS_KEY=$(openssl rand -hex 16)
  SECRET_KEY=$(openssl rand -hex 32)

  echo "Creating S3 credentials for: $service"

  run_weed_shell "s3.configure -apply -user $service -access_key $ACCESS_KEY -secret_key $SECRET_KEY -actions Read,Write,List,Tagging -buckets $service"

  # Store credentials as K8s secret
  $KUBECTL create secret generic "seaweedfs-${service}" \
    --namespace "$NAMESPACE" \
    --from-literal=access-key-id="$ACCESS_KEY" \
    --from-literal=secret-key="$SECRET_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f -

  echo "Credentials for $service stored in secret seaweedfs-${service}"
done

echo "Buckets and service credentials created."
