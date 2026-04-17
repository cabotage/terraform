# --- CloudNativePG Operator ---
# Step 6 in start-cluster
#
# Existing clusters — import before apply:
#
#   terraform import 'module.cabotage.helm_release.cnpg' 'postgres/cnpg'

resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  namespace        = "postgres"
  create_namespace = true
  version          = var.cnpg_chart_version

  values = [yamlencode({
    podLabels = {
      "cabotage.io/infra" = "true"
    }
  })]
}

resource "helm_release" "barman_cloud_plugin" {
  name       = "plugin-barman-cloud"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "plugin-barman-cloud"
  namespace  = "postgres"
  version    = var.barman_cloud_plugin_chart_version

  depends_on = [
    helm_release.cnpg,
    helm_release.cert_manager,
  ]
}
