#!/usr/bin/env bash
# Helm postrender script: strips the ProxyGroup CRD from the rendered manifests
# so terraform can manage the fork's version (with spec.tailnet) separately.
#
# Used by: helm_release.tailscale_operator in tailscale-operator-manager.tf
# See: https://helm.sh/docs/topics/advanced/#post-rendering

set -euo pipefail

# Read all manifests from stdin, split on ---, drop any doc that is a
# CustomResourceDefinition named proxygroups.tailscale.com, emit the rest.
awk '
/^---$/ {
    if (buf != "" && !drop) {
        if (printed) printf "---\n"
        printf "%s", buf
        printed=1
    }
    buf=""
    drop=0
    next
}
{
    buf = (buf == "" ? $0 "\n" : buf $0 "\n")
    if ($0 ~ /^  name: proxygroups\.tailscale\.com/) drop=1
}
END {
    if (buf != "" && !drop) {
        if (printed) printf "---\n"
        printf "%s", buf
    }
}
'
