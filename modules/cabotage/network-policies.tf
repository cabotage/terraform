# --- Network Policies ---
#
# Default-deny ingress on all managed namespaces, with targeted allow policies
# per component. See NETWORK-POLICIES.md for the full communication map.

# --- Default Deny ---

resource "kubectl_manifest" "netpol_default_deny_cabotage" {
  yaml_body = file("${path.module}/manifests/network-policies/00-default-deny-cabotage.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_default_deny_postgres" {
  yaml_body = file("${path.module}/manifests/network-policies/00-default-deny-postgres.yml")

  depends_on = [kubernetes_namespace_v1.postgres]
}

resource "kubectl_manifest" "netpol_default_deny_redis" {
  yaml_body = file("${path.module}/manifests/network-policies/00-default-deny-redis.yml")

  depends_on = [helm_release.redis_operator]
}

# --- cabotage namespace: allow policies ---

resource "kubectl_manifest" "netpol_allow_cabotage_app_web" {
  yaml_body = templatefile("${path.module}/manifests/network-policies/01-allow-cabotage-app-web.yml.tftpl", {
    traefik_host_network = var.traefik_host_network
    node_cidr            = var.node_cidr
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_vault" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-vault.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_consul" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-consul.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_registry" {
  yaml_body = templatefile("${path.module}/manifests/network-policies/01-allow-registry.yml.tftpl", {
    traefik_host_network = var.traefik_host_network
    node_cidr            = var.node_cidr
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_rustfs" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-rustfs.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_ca_admission" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-ca-admission.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_alloy" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-alloy.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_mimir" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-mimir.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "netpol_allow_loki" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-loki.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- postgres namespace ---

resource "kubectl_manifest" "netpol_allow_postgres" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-postgres.yml")

  depends_on = [kubernetes_namespace_v1.postgres]
}

# --- redis namespace ---

resource "kubectl_manifest" "netpol_allow_redis" {
  yaml_body = file("${path.module}/manifests/network-policies/01-allow-redis.yml")

  depends_on = [helm_release.redis_operator]
}
