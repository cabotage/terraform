#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=cabotage

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Fixing test deployments..."

kubectl set env deployment/test-crashloop -n "$NAMESPACE" BREAK-
kubectl patch deployment test-crashloop -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo happy; sleep 3600"]}]'

kubectl set env deployment/test-oom -n "$NAMESPACE" BREAK-
kubectl patch deployment test-oom -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo happy; sleep 3600"]},{"op":"remove","path":"/spec/template/spec/containers/0/resources"}]'

kubectl set env deployment/test-unavail -n "$NAMESPACE" BREAK-
kubectl patch deployment test-unavail -n "$NAMESPACE" --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"busybox"},{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo happy; sleep 3600"]}]'

kubectl rollout restart deployment/test-crashloop deployment/test-oom deployment/test-unavail -n "$NAMESPACE"

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Done. All test deployments fixed with fresh pods."
