# --- Tenant Log Export (optional) ---
#
# Manifests live in manifests/resident-monitoring/tenant-log-export/.
# resident-alloy forwards opted-in tenant pods' logs over OTLP to this
# Fluent Bit, which sends each tenant's logs to its own Datadog account.
# cabotage-app writes one output per application environment into the
# tenant-log-export Secret; the reload sidecar hot-reloads Fluent Bit.
# See docs/log-export.md in cabotage-app for the contract.

resource "kubectl_manifest" "tenant_log_export_certificate" {
  count     = var.enable_log_export ? 1 : 0
  yaml_body = file("${path.module}/manifests/resident-monitoring/tenant-log-export/00-certificate.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.sign_intermediate_cas,
  ]
}

resource "kubernetes_secret_v1" "tenant_log_export" {
  count = var.enable_log_export ? 1 : 0

  metadata {
    name      = "tenant-log-export"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  # Fluent Bit rejects an include glob that matches nothing.
  data = {
    "00-placeholder.yaml" = ""
  }

  # cabotage-app adds and removes the <namespace>.<app>.yaml outputs.
  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubectl_manifest" "tenant_log_export_configmap" {
  count     = var.enable_log_export ? 1 : 0
  yaml_body = file("${path.module}/manifests/resident-monitoring/tenant-log-export/01-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "tenant_log_export_statefulset" {
  count = var.enable_log_export ? 1 : 0
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/tenant-log-export/02-statefulset.yml.tftpl", {
    resources = var.tenant_log_export_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.tenant_log_export_certificate,
    kubernetes_secret_v1.tenant_log_export,
    kubectl_manifest.tenant_log_export_configmap,
  ]
}

resource "kubectl_manifest" "tenant_log_export_service" {
  count     = var.enable_log_export ? 1 : 0
  yaml_body = file("${path.module}/manifests/resident-monitoring/tenant-log-export/03-service.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "tenant_log_export_pdb" {
  count     = var.enable_log_export ? 1 : 0
  yaml_body = file("${path.module}/manifests/resident-monitoring/tenant-log-export/04-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}
