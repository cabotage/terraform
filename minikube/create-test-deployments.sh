#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=cabotage

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Creating test deployments..."

kubectl apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-happy
  namespace: cabotage
  labels:
    app: test-happy
    resident-deployment.cabotage.io: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-happy
  template:
    metadata:
      labels:
        app: test-happy
    spec:
      containers:
      - name: happy
        image: busybox
        command: ["sh", "-c", "echo happy; sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-crashloop
  namespace: cabotage
  labels:
    app: test-crashloop
    resident-deployment.cabotage.io: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-crashloop
  template:
    metadata:
      labels:
        app: test-crashloop
    spec:
      containers:
      - name: crashloop
        image: busybox
        command: ["sh", "-c", "echo happy; sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-oom
  namespace: cabotage
  labels:
    app: test-oom
    resident-deployment.cabotage.io: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-oom
  template:
    metadata:
      labels:
        app: test-oom
    spec:
      containers:
      - name: oom
        image: busybox
        command: ["sh", "-c", "echo happy; sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-unavail
  namespace: cabotage
  labels:
    app: test-unavail
    resident-deployment.cabotage.io: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-unavail
  template:
    metadata:
      labels:
        app: test-unavail
    spec:
      containers:
      - name: unavail
        image: busybox
        command: ["sh", "-c", "echo happy; sleep 3600"]
EOF

echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Done. All test deployments created in happy state."
