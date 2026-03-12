# --- Redis Operator + Cluster ---
# Step 6 in start-cluster (operator installed alongside CNPG)
#
# Manifests live in manifests/redis/.
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

# --- Password Secret ---

resource "random_password" "redis_password" {
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "redis_password" {
  metadata {
    name      = "cabotage-password"
    namespace = "redis"
  }

  data = {
    password = random_password.redis_password.result
  }

  lifecycle {
    ignore_changes = [data]
  }

  depends_on = [helm_release.redis_operator]
}

# --- TLS Certificate ---

resource "kubectl_manifest" "redis_certificate" {
  yaml_body = file("${path.module}/manifests/redis/cert.yaml")

  depends_on = [
    helm_release.redis_operator,
    kubectl_manifest.operators_ca_issuer,
    null_resource.sign_intermediate_cas,
  ]
}

# --- Redis Cluster ---

resource "kubectl_manifest" "redis_cluster" {
  yaml_body = file("${path.module}/manifests/redis/redis.yaml")

  wait_for_rollout = false

  depends_on = [
    helm_release.redis_operator,
    kubernetes_secret_v1.redis_password,
    kubectl_manifest.redis_certificate,
  ]
}
