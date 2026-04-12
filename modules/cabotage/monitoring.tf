# --- Resident Monitoring (Alloy, Mimir, Loki) ---
#
# Manifests live in manifests/resident-monitoring/.
# When var.s3_storage is null, services use SeaweedFS with per-service
# credentials created by the seaweedfs-create-buckets script.
# When var.s3_storage is set, services use AWS S3 via IRSA.

locals {
  use_s3 = var.s3_storage != null
}

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
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/alloy/02-configmap.yml.tftpl", {
    cadvisor_insecure_skip_verify = var.alloy_cadvisor_insecure_skip_verify
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "alloy_cluster_service" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/alloy/04-service-cluster.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "alloy_daemonset" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/alloy/03-daemonset.yml.tftpl", {
    resources = var.alloy_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.alloy_clusterrolebinding,
    kubectl_manifest.alloy_configmap,
    kubectl_manifest.alloy_cluster_service,
    kubectl_manifest.loki_statefulset_write,
    kubectl_manifest.loki_statefulset_standalone,
    kubectl_manifest.mimir_statefulset_write,
    kubectl_manifest.mimir_statefulset_standalone,
    kubectl_manifest.ksm_service,
  ]
}

resource "null_resource" "alloy_configmap_rollout" {
  lifecycle {
    replace_triggered_by = [kubectl_manifest.alloy_configmap]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage daemonset/resident-alloy
      kubectl --context ${var.kube_context} rollout status -n cabotage daemonset/resident-alloy --timeout=300s
    EOT
  }

  depends_on = [kubectl_manifest.alloy_daemonset]
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
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/00-serviceaccount.yml.tftpl", {
    role_arn = local.use_s3 ? var.s3_storage.loki_role_arn : ""
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_configmap" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/01-configmap.yml.tftpl", {
    use_s3    = local.use_s3
    s3_bucket = local.use_s3 ? var.s3_storage.loki_bucket : ""
    s3_region = local.use_s3 ? var.s3_storage.region : ""
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_statefulset_backend" {
  count = var.loki_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/02-statefulset-backend.yml", {
    replicas  = var.loki_backend_replicas
    use_s3    = local.use_s3
    resources = var.loki_backend_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_statefulset_read" {
  count = var.loki_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/02-statefulset-read.yml", {
    replicas  = var.loki_read_replicas
    use_s3    = local.use_s3
    resources = var.loki_read_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_statefulset_write" {
  count = var.loki_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/02-statefulset-write.yml", {
    replicas  = var.loki_write_replicas
    use_s3    = local.use_s3
    resources = var.loki_write_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_statefulset_standalone" {
  count = var.loki_standalone ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/02-statefulset-standalone.yml", {
    use_s3    = local.use_s3
    resources = var.loki_standalone_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.loki_serviceaccount,
    kubectl_manifest.loki_configmap,
    kubectl_manifest.loki_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "loki_service_backend" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/03-service-backend.yml.tftpl", {
    component = var.loki_standalone ? "standalone" : "backend"
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_memberlist" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/loki/03-service-memberlist.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_read" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/03-service-read.yml.tftpl", {
    component = var.loki_standalone ? "standalone" : "read"
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "loki_service_write" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/loki/03-service-write.yml.tftpl", {
    component = var.loki_standalone ? "standalone" : "write"
  })

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
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/kube-state-metrics/02-deployment.yml.tftpl", {
    resources = var.kube_state_metrics_resources
  })

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
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/00-serviceaccount.yml.tftpl", {
    role_arn = local.use_s3 ? var.s3_storage.mimir_role_arn : ""
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/01-configmap.yml.tftpl", {
    use_s3    = local.use_s3
    s3_bucket = local.use_s3 ? var.s3_storage.mimir_bucket : ""
    s3_region = local.use_s3 ? var.s3_storage.region : ""
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap_rules" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/01-configmap-rules.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_configmap_alertmanager" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/01-configmap-alertmanager.yml.tftpl", {
    alertmanager_webhook_secret = random_password.alertmanager_webhook_secret.result
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_statefulset_backend" {
  count = var.mimir_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-backend.yml", {
    replicas  = var.mimir_backend_replicas
    use_s3    = local.use_s3
    resources = var.mimir_backend_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_configmap_alertmanager,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_statefulset_read" {
  count = var.mimir_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-read.yml", {
    replicas  = var.mimir_read_replicas
    use_s3    = local.use_s3
    resources = var.mimir_read_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_statefulset_write" {
  count = var.mimir_standalone ? 0 : 1

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-write.yml", {
    replicas  = var.mimir_write_replicas
    use_s3    = local.use_s3
    resources = var.mimir_write_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "kubectl_manifest" "mimir_statefulset_standalone" {
  count = var.mimir_standalone ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/02-statefulset-standalone.yml", {
    use_s3    = local.use_s3
    resources = var.mimir_standalone_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.mimir_serviceaccount,
    kubectl_manifest.mimir_configmap,
    kubectl_manifest.mimir_configmap_rules,
    kubectl_manifest.mimir_configmap_alertmanager,
    kubectl_manifest.mimir_certificate,
    null_resource.ca_admission_webhook_ready,
    null_resource.seaweedfs_create_buckets,
  ]
}

resource "null_resource" "mimir_configmap_rollout_standalone" {
  count = var.mimir_standalone ? 1 : 0

  lifecycle {
    replace_triggered_by = [
      kubectl_manifest.mimir_configmap,
      kubectl_manifest.mimir_configmap_rules,
      kubectl_manifest.mimir_configmap_alertmanager,
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage statefulset/resident-mimir-standalone
      kubectl --context ${var.kube_context} rollout status -n cabotage statefulset/resident-mimir-standalone --timeout=300s
    EOT
  }

  depends_on = [kubectl_manifest.mimir_statefulset_standalone]
}

resource "null_resource" "mimir_configmap_rollout_backend" {
  count = var.mimir_standalone ? 0 : 1

  lifecycle {
    replace_triggered_by = [
      kubectl_manifest.mimir_configmap,
      kubectl_manifest.mimir_configmap_rules,
      kubectl_manifest.mimir_configmap_alertmanager,
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage statefulset/resident-mimir-backend
      kubectl --context ${var.kube_context} rollout status -n cabotage statefulset/resident-mimir-backend --timeout=300s
    EOT
  }

  depends_on = [kubectl_manifest.mimir_statefulset_backend]
}

resource "null_resource" "mimir_configmap_rollout_write" {
  count = var.mimir_standalone ? 0 : 1

  lifecycle {
    replace_triggered_by = [
      kubectl_manifest.mimir_configmap,
      kubectl_manifest.mimir_configmap_rules,
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage statefulset/resident-mimir-write
      kubectl --context ${var.kube_context} rollout status -n cabotage statefulset/resident-mimir-write --timeout=300s
    EOT
  }

  depends_on = [kubectl_manifest.mimir_statefulset_write]
}

resource "null_resource" "mimir_configmap_rollout_read" {
  count = var.mimir_standalone ? 0 : 1

  lifecycle {
    replace_triggered_by = [
      kubectl_manifest.mimir_configmap,
      kubectl_manifest.mimir_configmap_rules,
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage statefulset/resident-mimir-read
      kubectl --context ${var.kube_context} rollout status -n cabotage statefulset/resident-mimir-read --timeout=300s
    EOT
  }

  depends_on = [kubectl_manifest.mimir_statefulset_read]
}

resource "kubectl_manifest" "mimir_service_backend" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/03-service-backend.yml.tftpl", {
    component = var.mimir_standalone ? "standalone" : "backend"
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_memberlist" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/03-service-memberlist.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_read" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/03-service-read.yml.tftpl", {
    component = var.mimir_standalone ? "standalone" : "read"
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_service_write" {
  yaml_body = templatefile("${path.module}/manifests/resident-monitoring/mimir/03-service-write.yml.tftpl", {
    component = var.mimir_standalone ? "standalone" : "write"
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "mimir_pdb" {
  yaml_body = file("${path.module}/manifests/resident-monitoring/mimir/04-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}
