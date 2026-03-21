# --- RustFS (S3-compatible object storage) ---
#
# Replaces MinIO. Manifests live in manifests/rustfs/.
# Only the StatefulSet is templated (for replicas and image).
#
# Skipped entirely when var.s3_storage is set (AWS S3 used instead).

# --- Admin Credentials ---

resource "null_resource" "rustfs_admin_secret" {
  count = local.use_s3 ? 0 : 1

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = "sh ${path.module}/scripts/rustfs-create-admin-secret.sh"
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Manifests ---

resource "kubectl_manifest" "rustfs_serviceaccount" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/rustfs/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "rustfs_service_headless" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/rustfs/01-service-headless.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

locals {
  rustfs_disks = var.rustfs_disks_per_replica
  # Single replica + single disk = FS mode (no erasure coding)
  rustfs_volumes_arg = (
    var.rustfs_replicas == 1 && local.rustfs_disks == 1
    ? "/mnt/rustfs0"
    : "https://rustfs-{0...${var.rustfs_replicas - 1}}.rustfs.cabotage.svc.cluster.local:9000/mnt/rustfs{0...${local.rustfs_disks - 1}}"
  )
}

resource "kubectl_manifest" "rustfs_statefulset" {
  count = local.use_s3 ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/rustfs/01-statefulset.yml.tftpl", {
    replicas            = var.rustfs_replicas
    rustfs_image        = var.rustfs_image
    rustfs_storage_size = var.rustfs_storage_size
    rustfs_log_size     = var.rustfs_log_size
    disks_per_replica   = var.rustfs_disks_per_replica
    rustfs_volumes_arg  = local.rustfs_volumes_arg
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
    null_resource.rustfs_admin_secret,
    kubectl_manifest.rustfs_serviceaccount,
    kubectl_manifest.rustfs_service_headless,
  ]
}

resource "kubectl_manifest" "rustfs_console_service_headless" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/rustfs/02-console-service-headless.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Bucket Creation ---

resource "null_resource" "rustfs_create_buckets" {
  count = local.use_s3 ? 0 : 1

  triggers = {
    statefulset_id = kubectl_manifest.rustfs_statefulset[0].id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/rustfs-create-buckets.sh"
    environment = {
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    }
  }

  depends_on = [kubectl_manifest.rustfs_statefulset]
}
