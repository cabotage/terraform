# --- Resident Monitoring (Alloy, Mimir, Loki) ---
#
# Manifests live in manifests/resident-monitoring/.
# All manifests are static copies from kubernetes-infra with minio
# endpoint changed to rustfs. Per-service S3 credentials are created
# by the rustfs-create-buckets script (secrets: rustfs-resident-loki,
# rustfs-resident-mimir).

# --- Alloy ---

resource "kubectl_manifest" "alloy_clusterrole" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/00-clusterrole.yml")
}

resource "kubectl_manifest" "alloy_serviceaccount" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "alloy_clusterrolebinding" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/01-clusterrolebinding.yml")

  depends_on = [
    kubectl_manifest.alloy_clusterrole,
    kubectl_manifest.alloy_serviceaccount,
  ]
}

resource "kubectl_manifest" "alloy_configmap" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/02-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "alloy_daemonset" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/03-daemonset.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.alloy_clusterrolebinding,
    kubectl_manifest.alloy_configmap,
    kubectl_manifest.loki_statefulset_write,
    kubectl_manifest.mimir_statefulset_write,
    kubectl_manifest.ksm_service,
  ]
}

# --- Loki ---

resource "kubectl_manifest" "loki_certificate" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/00-certificate.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.sign_intermediate_cas,
  ]
}

resource "kubectl_manifest" "loki_serviceaccount" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_configmap" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/01-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_statefulset_backend" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/02-statefulset-backend.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_statefulset_read" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/02-statefulset-read.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_statefulset_write" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/02-statefulset-write.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_service_backend" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/03-service-backend.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_memberlist" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/03-service-memberlist.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_read" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/03-service-read.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_write" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/03-service-write.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_pdb" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/04-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Kube State Metrics ---

resource "kubectl_manifest" "ksm_certificate" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/00-certificate.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.sign_intermediate_cas,
  ]
}

resource "kubectl_manifest" "ksm_serviceaccount" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "ksm_clusterrole" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/00-clusterrole.yml")
}

resource "kubectl_manifest" "ksm_clusterrolebinding" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/01-clusterrolebinding.yml")

  depends_on = [
    kubectl_manifest.ksm_clusterrole,
    kubectl_manifest.ksm_serviceaccount,
  ]
}

resource "kubectl_manifest" "ksm_configmap" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/01-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "ksm_deployment" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/02-deployment.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.ksm_clusterrolebinding,
    kubectl_manifest.ksm_configmap,
    kubectl_manifest.ksm_certificate,
    null_resource.ca_admission_webhook_ready,
  ]
}

resource "kubectl_manifest" "ksm_service" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/kube-state-metrics/03-service.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Mimir ---

resource "kubectl_manifest" "mimir_certificate" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/00-certificate.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.sign_intermediate_cas,
  ]
}

resource "kubectl_manifest" "mimir_serviceaccount" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/01-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap_rules" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/01-configmap-rules.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap_alertmanager" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/01-configmap-alertmanager.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_statefulset_backend" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-backend.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_configmap_alertmanager,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_statefulset_read" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-read.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_statefulset_write" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-write.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.rustfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_service_backend" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/03-service-backend.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_memberlist" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/03-service-memberlist.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_read" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/03-service-read.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_write" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/03-service-write.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_pdb" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/04-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}
