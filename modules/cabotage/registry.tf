# --- Container Registry ---
# Step 15 in start-cluster
#
# Manifests live in manifests/registry/.
# Post-deploy script fetches signing cert from cabotage-app and patches config.

locals {
  registry_configmap = templatefile("${path.module}/manifests/registry/01-configmap.yml.tftpl", {
    hostname       = var.cabotage_app_hostname
    ingress_domain = var.cabotage_ingress_domain
  })
  registry_config_hash = sha256(local.registry_configmap)
}

# --- RBAC ---

resource "kubectl_manifest" "registry_serviceaccount" {
  yaml_body = file("${path.module}/manifests/registry/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- ConfigMap ---

resource "kubectl_manifest" "registry_configmap" {
  yaml_body = local.registry_configmap

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Deployment ---

resource "kubectl_manifest" "registry_deployment" {
  yaml_body = templatefile("${path.module}/manifests/registry/02-deployment.yml.tftpl", {
    config_hash = local.registry_config_hash
    replicas    = var.registry_replicas
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.registry_serviceaccount,
    kubectl_manifest.registry_configmap,
    null_resource.ca_admission_webhook_ready,
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
  ]
}

# --- CronJob (Garbage Collection) ---

resource "kubectl_manifest" "registry_cronjob" {
  yaml_body = file("${path.module}/manifests/registry/02-cronjob.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Services ---

resource "kubectl_manifest" "registry_service_headless" {
  yaml_body = file("${path.module}/manifests/registry/03-service-headless.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "registry_service_ingress" {
  yaml_body = file("${path.module}/manifests/registry/03-service-ingress.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Ingress ---

resource "kubectl_manifest" "registry_ingress" {
  yaml_body = templatefile("${path.module}/manifests/registry/04-ingress.yml.tftpl", {
    ingress_domain = var.cabotage_ingress_domain
  })

  depends_on = [
    kubectl_manifest.registry_service_ingress,
    kubectl_manifest.nginx_ingress_class,
    helm_release.cert_manager,
  ]
}

# --- Post-deploy Configuration ---
# Fetches signing cert from cabotage-app, patches registry config, restarts.

resource "null_resource" "registry_configure" {
  triggers = {
    deployment_id = kubectl_manifest.registry_deployment.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/registry-configure.sh"
    environment = {
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    }
  }

  depends_on = [
    kubectl_manifest.registry_deployment,
    null_resource.cabotage_app_configure,
  ]
}
