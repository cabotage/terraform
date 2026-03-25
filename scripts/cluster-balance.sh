#!/usr/bin/env bash
set -euo pipefail

# Gather node info, pod requests, and usage in parallel
NODE_JSON=$(kubectl get nodes -o json)
POD_JSON=$(kubectl get pods --all-namespaces -o json)
TOP_OUTPUT=$(kubectl top nodes --no-headers 2>/dev/null || true)

# Build node table: name, pool, az, instance type, capacity type, allocatable cpu(m)/mem(Mi)
NODES=$(echo "$NODE_JSON" | jq -r '
  def parse_res: if test("m$") then (rtrimstr("m") | tonumber)
    elif test("Mi$") then (rtrimstr("Mi") | tonumber)
    elif test("Ki$") then (rtrimstr("Ki") | tonumber / 1024 | floor)
    elif test("Gi$") then (rtrimstr("Gi") | tonumber * 1024)
    else (tonumber * 1000) end;
  .items[] |
    (.metadata.labels["cabotage.dev/node-pool"] // "managed") as $pool |
    (.metadata.labels["topology.kubernetes.io/zone"]) as $az |
    (.metadata.labels["node.kubernetes.io/instance-type"]) as $type |
    (.metadata.labels["karpenter.sh/capacity-type"] // "on-demand") as $cap |
    (.status.allocatable.cpu | parse_res) as $cpu |
    (.status.allocatable.memory | parse_res) as $mem |
    [.metadata.name, $pool, $az, $type, $cap, ($cpu|tostring), ($mem|tostring)] | @tsv')

# Build per-node request sums (cpu in millicores, mem in MiB)
REQUESTS=$(echo "$POD_JSON" | jq -r '
  def parse_cpu: if . == "0" or . == null then 0
    elif test("m$") then (rtrimstr("m") | tonumber)
    else (tonumber * 1000) end;
  def parse_mem: if . == "0" or . == null then 0
    elif test("Gi$") then (rtrimstr("Gi") | tonumber * 1024)
    elif test("Mi$") then (rtrimstr("Mi") | tonumber)
    elif test("Ki$") then (rtrimstr("Ki") | tonumber / 1024)
    else 0 end;
  [.items[] | select(.status.phase == "Running") |
    .spec.nodeName as $node |
    .spec.containers[] |
    {node: $node,
     cpu_req: ((.resources.requests.cpu // "0") | parse_cpu),
     mem_req: ((.resources.requests.memory // "0") | parse_mem)}] |
  group_by(.node) | map({
    node: .[0].node,
    cpu_req: (map(.cpu_req) | add),
    mem_req: (map(.mem_req) | add | floor)
  }) | .[] | [.node, (.cpu_req|tostring), (.mem_req|tostring)] | @tsv')

# Build per-node usage from kubectl top (cpu in millicores, mem in MiB)
declare -A USAGE_CPU USAGE_MEM
while IFS=$'\t ' read -r name cpu _ mem _; do
  [[ -z "$name" ]] && continue
  if [[ "$cpu" == *m ]]; then
    USAGE_CPU[$name]="${cpu%m}"
  else
    USAGE_CPU[$name]=$(( ${cpu} * 1000 ))
  fi
  if [[ "$mem" == *Mi ]]; then
    USAGE_MEM[$name]="${mem%Mi}"
  elif [[ "$mem" == *Gi ]]; then
    USAGE_MEM[$name]=$(( ${mem%Gi} * 1024 ))
  else
    USAGE_MEM[$name]="$mem"
  fi
done <<< "$TOP_OUTPUT"

# Index requests by node
declare -A REQ_CPU REQ_MEM
while IFS=$'\t' read -r node cpu mem; do
  REQ_CPU[$node]="$cpu"
  REQ_MEM[$node]="$mem"
done <<< "$REQUESTS"

# --- Per-node detail table ---
dfmt="%-42s  %-9s  %-12s  %-13s  %-9s  %6s / %6s  %4s  %8s / %8s  %4s  %6s  %4s  %8s  %4s\n"

printf "\n"
printf "$dfmt" \
  "NODE" "POOL" "AZ" "TYPE" "CAP" \
  "C.REQ" "C.CAP" "RQ%" \
  "M.REQ" "M.CAP" "RQ%" \
  "C.USE" "US%" \
  "M.USE" "US%"
printf "%s\n" "$(printf '%.0s─' {1..173})"

echo "$NODES" | sort -t$'\t' -k2,2 -k3,3 | while IFS=$'\t' read -r name pool az type cap alloc_cpu alloc_mem; do
  cpu_req=${REQ_CPU[$name]:-0}
  mem_req=${REQ_MEM[$name]:-0}
  cpu_use=${USAGE_CPU[$name]:-0}
  mem_use=${USAGE_MEM[$name]:-0}

  cpu_req_pct=0; [[ $alloc_cpu -gt 0 ]] && cpu_req_pct=$(( cpu_req * 100 / alloc_cpu ))
  mem_req_pct=0; [[ $alloc_mem -gt 0 ]] && mem_req_pct=$(( mem_req * 100 / alloc_mem ))
  cpu_use_pct=0; [[ $alloc_cpu -gt 0 ]] && cpu_use_pct=$(( cpu_use * 100 / alloc_cpu ))
  mem_use_pct=0; [[ $alloc_mem -gt 0 ]] && mem_use_pct=$(( mem_use * 100 / alloc_mem ))

  printf "$dfmt" \
    "$name" "$pool" "$az" "$type" "$cap" \
    "${cpu_req}m" "${alloc_cpu}m" "${cpu_req_pct}%" \
    "${mem_req}Mi" "${alloc_mem}Mi" "${mem_req_pct}%" \
    "${cpu_use}m" "${cpu_use_pct}%" \
    "${mem_use}Mi" "${mem_use_pct}%"
done

# --- Pool summary table ---
sfmt="%-9s  %5s  %-18s  %7s / %7s  %4s  %8s / %8s  %4s  %7s  %4s  %8s  %4s\n"

printf "\n"
printf "$sfmt" \
  "POOL" "NODES" "AZ SPREAD" \
  "C.REQ" "C.CAP" "RQ%" \
  "M.REQ" "M.CAP" "RQ%" \
  "C.USE" "US%" \
  "M.USE" "US%"
printf "%s\n" "$(printf '%.0s─' {1..119})"

echo "$NODES" | sort -t$'\t' -k2,2 | \
  awk -F'\t' '{print $2}' | uniq | while read -r pool; do
  pool_nodes=$(echo "$NODES" | awk -F'\t' -v p="$pool" '$2 == p')
  n_nodes=$(echo "$pool_nodes" | wc -l | tr -d ' ')

  az_spread=$(echo "$pool_nodes" | awk -F'\t' '{print $3}' | sort | uniq -c | sort -k2 |
    awk '{sub(/.*-/, "", $2); printf "%s:%s ", $2, $1}')

  total_alloc_cpu=0; total_alloc_mem=0
  total_req_cpu=0; total_req_mem=0
  total_use_cpu=0; total_use_mem=0

  while IFS=$'\t' read -r name _ _ _ _ alloc_cpu alloc_mem; do
    total_alloc_cpu=$(( total_alloc_cpu + alloc_cpu ))
    total_alloc_mem=$(( total_alloc_mem + alloc_mem ))
    total_req_cpu=$(( total_req_cpu + ${REQ_CPU[$name]:-0} ))
    total_req_mem=$(( total_req_mem + ${REQ_MEM[$name]:-0} ))
    total_use_cpu=$(( total_use_cpu + ${USAGE_CPU[$name]:-0} ))
    total_use_mem=$(( total_use_mem + ${USAGE_MEM[$name]:-0} ))
  done <<< "$pool_nodes"

  req_cpu_pct=0; [[ $total_alloc_cpu -gt 0 ]] && req_cpu_pct=$(( total_req_cpu * 100 / total_alloc_cpu ))
  req_mem_pct=0; [[ $total_alloc_mem -gt 0 ]] && req_mem_pct=$(( total_req_mem * 100 / total_alloc_mem ))
  use_cpu_pct=0; [[ $total_alloc_cpu -gt 0 ]] && use_cpu_pct=$(( total_use_cpu * 100 / total_alloc_cpu ))
  use_mem_pct=0; [[ $total_alloc_mem -gt 0 ]] && use_mem_pct=$(( total_use_mem * 100 / total_alloc_mem ))

  printf "$sfmt" \
    "$pool" "$n_nodes" "$az_spread" \
    "${total_req_cpu}m" "${total_alloc_cpu}m" "${req_cpu_pct}%" \
    "${total_req_mem}Mi" "${total_alloc_mem}Mi" "${req_mem_pct}%" \
    "${total_use_cpu}m" "${use_cpu_pct}%" \
    "${total_use_mem}Mi" "${use_mem_pct}%"
done
