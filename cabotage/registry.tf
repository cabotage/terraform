# --- Container Registry ---
# Step 15 in start-cluster
#
# Manifests live in manifests/registry/.
# Post-deploy script fetches signing cert from cabotage-app and patches config.

# --- RBAC ---

resource "kubectl_manifest" "registry_serviceaccount" {
  yaml_body = file("${path.module}/manifests/registry/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Enrollment ---

resource "kubectl_manifest" "registry_enrollment" {
  yaml_body = file("${path.module}/manifests/registry/00-enrollment.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.enrollment_operator_deployment,
  ]
}

# --- Wait for Enrollment to be processed ---

resource "null_resource" "registry_enrollment_ready" {
  triggers = {
    enrollment_id = kubectl_manifest.registry_enrollment.id
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = <<-EOT
      echo "Waiting for registry enrollment to be ready..."
      for i in $(seq 1 60); do
        ready=$(kubectl --context $KUBE_CONTEXT get cabotageenrollment registry -n cabotage -o jsonpath='{.status.summary.ready}' 2>/dev/null)
        if [ "$ready" = "true" ]; then
          echo "Enrollment ready."
          exit 0
        fi
        [ $((i % 12)) -eq 0 ] && echo "  Still waiting... ($i attempts)"
        sleep 5
      done
      echo "ERROR: Timed out after 300s waiting for registry enrollment"
      kubectl --context $KUBE_CONTEXT get cabotageenrollment registry -n cabotage -o yaml 2>&1 || true
      exit 1
    EOT
  }

  depends_on = [
    kubectl_manifest.registry_enrollment,
    null_resource.vault_bootstrap,
    null_resource.consul_bootstrap,
  ]
}

# --- ConfigMap ---

resource "kubectl_manifest" "registry_configmap" {
  yaml_body = file("${path.module}/manifests/registry/01-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Deployment ---

resource "kubectl_manifest" "registry_deployment" {
  yaml_body = file("${path.module}/manifests/registry/02-deployment.yml")

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.registry_serviceaccount,
    null_resource.registry_enrollment_ready,
    kubectl_manifest.registry_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
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
