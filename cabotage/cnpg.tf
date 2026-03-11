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
}
