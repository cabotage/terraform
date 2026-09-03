# --- ClickHouse Operator ---
# First-party operator (ClickHouse/clickhouse-operator), published OCI-only.
#
# Opt-in, unlike cnpg/redis: not every cluster runs analytics workloads.
#
# Namespace must be "clickhouse": tenant NetworkPolicies allow app egress to
# that namespace on 8443/9440 (see cabotage-app deploy.py).
#
# Existing clusters — import before apply:
#
#   terraform import 'module.cabotage.helm_release.clickhouse_operator[0]' 'clickhouse/clickhouse-operator'

resource "helm_release" "clickhouse_operator" {
  count = var.enable_clickhouse_operator ? 1 : 0

  name             = "clickhouse-operator"
  repository       = "oci://ghcr.io/clickhouse"
  chart            = "clickhouse-operator-helm"
  namespace        = "clickhouse"
  create_namespace = true
  version          = var.clickhouse_operator_chart_version

  values = [yamlencode({
    controller = {
      watchNamespaces = []
    }
    manager = {
      pod = {
        labels = {
          "cabotage.io/infra" = "true"
        }
      }
    }
  })]

  depends_on = [
    helm_release.cert_manager,
  ]
}
