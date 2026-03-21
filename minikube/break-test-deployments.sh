#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=cabotage
TS=$(date +%s)

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Breaking test deployments..."

kubectl set env deployment/test-crashloop -n "$NAMESPACE" BREAK="$TS"
kubectl patch deployment test-crashloop -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo about to crash; exit 1"]}]'

kubectl set env deployment/test-oom -n "$NAMESPACE" BREAK="$TS"
kubectl patch deployment test-oom -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo about to OOM; tail /dev/zero"]},{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"limits":{"memory":"8Mi"}}}]'

kubectl set env deployment/test-unavail -n "$NAMESPACE" BREAK="$TS"
kubectl patch deployment test-unavail -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"busybox:nonexistent-tag-that-does-not-exist"}]'

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Done. test-crashloop, test-oom, and test-unavail are broken."
