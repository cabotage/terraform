# --- Redis Operator ---
# Step 6 in start-cluster (installed alongside CNPG)
#
# Existing clusters — import before apply:
#
#   terraform import 'module.cabotage.helm_release.redis_operator' 'redis/redis-operator'

resource "helm_release" "redis_operator" {
  name             = "redis-operator"
  repository       = "https://ot-container-kit.github.io/helm-charts/"
  chart            = "redis-operator"
  namespace        = "redis"
  create_namespace = true
  version          = var.redis_operator_chart_version

  values = [yamlencode({
    watch_namespace = "redis"
  })]
}
