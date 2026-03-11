# --- RustFS (S3-compatible object storage) ---
#
# Replaces MinIO. Manifests live in manifests/rustfs/.
# Only the StatefulSet is templated (for replicas and image).

# --- Admin Credentials ---

resource "null_resource" "rustfs_admin_secret" {
  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/rustfs-create-admin-secret.sh"
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Manifests ---

resource "kubectl_manifest" "rustfs_serviceaccount" {
  yaml_body = file("${path.module}/manifests/rustfs/00-serviceaccount.yml")
}

resource "kubectl_manifest" "rustfs_service_headless" {
  yaml_body = file("${path.module}/manifests/rustfs/01-service-headless.yml")
}

resource "kubectl_manifest" "rustfs_statefulset" {
  yaml_body = templatefile("${path.module}/manifests/rustfs/01-statefulset.yml.tftpl", {
    replicas    = var.rustfs_replicas
    rustfs_image = var.rustfs_image
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
  yaml_body = file("${path.module}/manifests/rustfs/02-console-service-headless.yml")
}

# --- Bucket Creation ---

resource "null_resource" "rustfs_create_buckets" {
  triggers = {
    statefulset_id = kubectl_manifest.rustfs_statefulset.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/rustfs-create-buckets.sh"
    environment = {
      NAMESPACE = kubernetes_namespace_v1.cabotage.metadata[0].name
    }
  }

  depends_on = [kubectl_manifest.rustfs_statefulset]
}
