# --- SeaweedFS (S3-compatible object storage) ---
#
# Manifests live in manifests/seaweedfs/.
# Supports standalone mode (weed mini, all-in-one process) and clustered
# mode (separate master, volume, filer, s3 StatefulSets).
#
# Skipped entirely when var.s3_storage is set (AWS S3 used instead).

# --- Admin Credentials ---

resource "null_resource" "seaweedfs_admin_secret" {
  count = local.use_s3 ? 0 : 1

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = "sh ${path.module}/scripts/seaweedfs-create-admin-secret.sh"
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Manifests ---

resource "kubectl_manifest" "seaweedfs_serviceaccount" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Clustered mode: master, volume, filer, s3 ---

locals {
  seaweedfs_master_peers = join(",", [
    for i in range(var.seaweedfs_master_replicas) :
    "seaweedfs-master-${i}.seaweedfs-master.cabotage.svc.cluster.local:9333"
  ])
  seaweedfs_filer_peers = join(",", [
    for i in range(var.seaweedfs_filer_replicas) :
    "seaweedfs-filer-${i}.seaweedfs-filer.cabotage.svc.cluster.local:8888"
  ])
}

resource "kubectl_manifest" "seaweedfs_service_master" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/01-service-master.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "seaweedfs_service_volume" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/01-service-volume.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "seaweedfs_service_filer" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/01-service-filer.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "seaweedfs_service_s3" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/${
    var.seaweedfs_standalone ? "01-service-s3-standalone.yml" : "01-service-s3.yml"
  }")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# Standalone UI service — exposes master/filer/volume web UIs from the
# standalone pod for `kubectl port-forward`. In clustered mode the existing
# seaweedfs-master and seaweedfs-filer services already expose these.
resource "kubectl_manifest" "seaweedfs_service_ui_standalone" {
  count = local.use_s3 || !var.seaweedfs_standalone ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/01-service-ui-standalone.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "seaweedfs_statefulset_master" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/seaweedfs/02-statefulset-master.yml.tftpl", {
    replicas            = var.seaweedfs_master_replicas
    seaweedfs_image     = var.seaweedfs_image
    master_peers        = local.seaweedfs_master_peers
    master_storage_size = var.seaweedfs_master_storage_size
    resources           = var.seaweedfs_master_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.seaweedfs_serviceaccount,
    kubectl_manifest.seaweedfs_service_master,
  ]
}

resource "kubectl_manifest" "seaweedfs_statefulset_volume" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/seaweedfs/02-statefulset-volume.yml.tftpl", {
    replicas            = var.seaweedfs_volume_replicas
    seaweedfs_image     = var.seaweedfs_image
    master_peers        = local.seaweedfs_master_peers
    volume_storage_size = var.seaweedfs_volume_storage_size
    resources           = var.seaweedfs_volume_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.seaweedfs_serviceaccount,
    kubectl_manifest.seaweedfs_service_volume,
    kubectl_manifest.seaweedfs_statefulset_master,
  ]
}

resource "kubectl_manifest" "seaweedfs_statefulset_filer" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/seaweedfs/02-statefulset-filer.yml.tftpl", {
    replicas           = var.seaweedfs_filer_replicas
    seaweedfs_image    = var.seaweedfs_image
    master_peers       = local.seaweedfs_master_peers
    filer_storage_size = var.seaweedfs_filer_storage_size
    resources          = var.seaweedfs_filer_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.seaweedfs_serviceaccount,
    kubectl_manifest.seaweedfs_service_filer,
    kubectl_manifest.seaweedfs_statefulset_master,
  ]
}

resource "kubectl_manifest" "seaweedfs_statefulset_s3" {
  count = local.use_s3 || var.seaweedfs_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/seaweedfs/02-statefulset-s3.yml.tftpl", {
    replicas        = var.seaweedfs_s3_replicas
    seaweedfs_image = var.seaweedfs_image
    filer_peers     = local.seaweedfs_filer_peers
    resources       = var.seaweedfs_s3_resources
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
    kubectl_manifest.seaweedfs_serviceaccount,
    kubectl_manifest.seaweedfs_service_s3,
    kubectl_manifest.seaweedfs_statefulset_filer,
  ]
}

# --- Standalone mode ---

resource "kubectl_manifest" "seaweedfs_statefulset_standalone" {
  count = local.use_s3 || !var.seaweedfs_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/seaweedfs/02-statefulset-standalone.yml.tftpl", {
    seaweedfs_image     = var.seaweedfs_image
    volume_storage_size = var.seaweedfs_volume_storage_size
    resources           = var.seaweedfs_standalone_resources
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
    null_resource.seaweedfs_admin_secret,
    kubectl_manifest.seaweedfs_serviceaccount,
    kubectl_manifest.seaweedfs_service_s3,
  ]
}

# --- Pod Disruption Budget ---

resource "kubectl_manifest" "seaweedfs_pdb" {
  count = local.use_s3 ? 0 : 1

  yaml_body = file("${path.module}/manifests/seaweedfs/03-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Bucket Creation ---

resource "null_resource" "seaweedfs_create_buckets" {
  count = local.use_s3 ? 0 : 1

  triggers = {
    statefulset_id = var.seaweedfs_standalone ? (
      kubectl_manifest.seaweedfs_statefulset_standalone[0].id
    ) : (
      kubectl_manifest.seaweedfs_statefulset_s3[0].id
    )
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/seaweedfs-create-buckets.sh"
    environment = {
      NAMESPACE            = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT         = var.kube_context
      SEAWEEDFS_STANDALONE = var.seaweedfs_standalone ? "true" : "false"
    }
  }

  depends_on = [
    kubectl_manifest.seaweedfs_statefulset_standalone,
    kubectl_manifest.seaweedfs_statefulset_s3,
  ]
}
