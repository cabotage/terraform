#!/bin/sh
set -e

NAMESPACE="${NAMESPACE:-cabotage}"
. "$(dirname "$0")/_lib.sh"
RUSTFS_URL="https://rustfs.${NAMESPACE}.svc.cluster.local:9000"

echo "Waiting for RustFS to be ready..."
$KUBECTL rollout status statefulset/rustfs -n "$NAMESPACE" --timeout=300s

# Clean up any leftover pods from previous runs
$KUBECTL delete pod -n "$NAMESPACE" -l run=rustfs-rc --ignore-not-found > /dev/null 2>&1

# --- Helper: run rc command in-cluster with unique pod name ---
run_rc() {
  local pod_name="rustfs-rc-$(openssl rand -hex 4)"
  $KUBECTL run "$pod_name" -n "$NAMESPACE" --rm -i --restart=Never \
    --image=rustfs/rc:latest \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "rc",
          "image": "rustfs/rc:latest",
          "command": ["sh", "-c", "rc alias set rustfs '"$RUSTFS_URL"' $RUSTFS_ACCESS_KEY $RUSTFS_SECRET_KEY --insecure && '"$1"'"],
          "env": [
            {"name": "RUSTFS_ACCESS_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_ACCESS_KEY"}}},
            {"name": "RUSTFS_SECRET_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_SECRET_KEY"}}}
          ]
        }]
      }
    }'
}

# --- Helper: run rc with retry ---
run_rc_retry() {
  attempt=1
  while [ $attempt -le 30 ]; do
    if run_rc "$1"; then
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
  run_rc_retry "rc mb --ignore-existing rustfs/$bucket"
done

# --- Create per-service users and policies ---
cleanup_configmaps() {
  for svc in resident-loki resident-mimir cabotage-registry; do
    $KUBECTL delete configmap "rustfs-policy-${svc}" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1 || true
  done
}
trap cleanup_configmaps EXIT

for service in resident-loki resident-mimir cabotage-registry; do
  ACCESS_KEY=$(openssl rand -hex 16)
  SECRET_KEY=$(openssl rand -hex 32)

  echo "Creating user and policy for: $service"

  # Write policy file into a ConfigMap, then mount it — too complex.
  # Instead, create user + use the built-in readwrite policy scoped via attachment.
  # For bucket-scoped policies, write the policy JSON to a file via kubectl exec.

  # Step 1: Create the user
  run_rc "rc admin user add rustfs $ACCESS_KEY $SECRET_KEY"

  # Step 2: Create a bucket-scoped policy via a temp ConfigMap
  POLICY_JSON="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetBucketLocation\",\"s3:ListBucket\",\"s3:ListBucketMultipartUploads\"],\"Resource\":[\"arn:aws:s3:::${service}\"]},{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListMultipartUploadParts\",\"s3:AbortMultipartUpload\"],\"Resource\":[\"arn:aws:s3:::${service}/*\"]}]}"

  $KUBECTL create configmap "rustfs-policy-${service}" \
    --namespace "$NAMESPACE" \
    --from-literal=policy.json="$POLICY_JSON" \
    --dry-run=client -o yaml | $KUBECTL apply -f -

  # Step 3: Run rc with the policy file mounted from the ConfigMap
  pod_name="rustfs-rc-$(openssl rand -hex 4)"
  $KUBECTL run "$pod_name" -n "$NAMESPACE" --rm -i --restart=Never \
    --image=rustfs/rc:latest \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "rc",
          "image": "rustfs/rc:latest",
          "command": ["sh", "-c", "rc alias set rustfs '"$RUSTFS_URL"' $RUSTFS_ACCESS_KEY $RUSTFS_SECRET_KEY --insecure && rc admin policy create rustfs '"${service}"'-policy /etc/rustfs-policy/policy.json && rc admin policy attach rustfs '"${service}"'-policy --user '"$ACCESS_KEY"'"],
          "env": [
            {"name": "RUSTFS_ACCESS_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_ACCESS_KEY"}}},
            {"name": "RUSTFS_SECRET_KEY", "valueFrom": {"secretKeyRef": {"name": "rustfs-admin", "key": "RUSTFS_SECRET_KEY"}}}
          ],
          "volumeMounts": [{"name": "policy", "mountPath": "/etc/rustfs-policy", "readOnly": true}]
        }],
        "volumes": [{"name": "policy", "configMap": {"name": "rustfs-policy-'"${service}"'"}}]
      }
    }'

  # Clean up temp configmap (run even on failure above)
  $KUBECTL delete configmap "rustfs-policy-${service}" -n "$NAMESPACE" > /dev/null || true

  # Store credentials as K8s secret
  $KUBECTL create secret generic "rustfs-${service}" \
    --namespace "$NAMESPACE" \
    --from-literal=access-key-id="$ACCESS_KEY" \
    --from-literal=secret-key="$SECRET_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f -

  echo "Credentials for $service stored in secret rustfs-${service}"
done

echo "Buckets and service credentials created."
