# --- Cabotage Application ---
# Step 14 in start-cluster
#
# Manifests live in manifests/cabotage-app/.
# Bootstrap script configures vault policy, consul policy, transit backend.
# Configure script patches DB/Redis/S3 URIs and runs DB migrations.

locals {
  cabotage_app_configmap = templatefile("${path.module}/manifests/cabotage-app/03-configmap.yml.tftpl", {
    hostname       = var.cabotage_app_hostname
    ingress_domain = var.cabotage_ingress_domain
  })
  cabotage_app_config_hash = sha256(local.cabotage_app_configmap)
}

# --- RBAC ---

resource "kubectl_manifest" "cabotage_app_role" {
  yaml_body = file("${path.module}/manifests/cabotage-app/00-role.yml")
}

resource "kubectl_manifest" "cabotage_app_serviceaccount" {
  yaml_body = file("${path.module}/manifests/cabotage-app/01-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "cabotage_app_rolebinding" {
  yaml_body = file("${path.module}/manifests/cabotage-app/02-rolebinding.yml")

  depends_on = [
    kubectl_manifest.cabotage_app_role,
    kubectl_manifest.cabotage_app_serviceaccount,
  ]
}

# --- Enrollment ---

resource "kubectl_manifest" "cabotage_app_enrollment" {
  yaml_body = file("${path.module}/manifests/cabotage-app/01-enrollment.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.enrollment_operator_deployment,
  ]
}

# --- Wait for Enrollment to be processed ---

resource "null_resource" "cabotage_app_enrollment_ready" {
  triggers = {
    enrollment_id = kubectl_manifest.cabotage_app_enrollment.id
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = <<-EOT
      echo "Waiting for cabotage-app enrollment to be ready..."
      for i in $(seq 1 60); do
        ready=$(kubectl --context $KUBE_CONTEXT get cabotageenrollment cabotage-app -n cabotage -o jsonpath='{.status.summary.ready}' 2>/dev/null)
        if [ "$ready" = "true" ]; then
          echo "Enrollment ready."
          exit 0
        fi
        [ $((i % 12)) -eq 0 ] && echo "  Still waiting... ($i attempts)"
        sleep 5
      done
      echo "ERROR: Timed out after 300s waiting for cabotage-app enrollment"
      kubectl --context $KUBE_CONTEXT get cabotageenrollment cabotage-app -n cabotage -o yaml 2>&1 || true
      exit 1
    EOT
  }

  depends_on = [
    kubectl_manifest.cabotage_app_enrollment,
    null_resource.vault_bootstrap,
    null_resource.consul_bootstrap,
  ]
}

# --- ConfigMap ---

resource "kubectl_manifest" "cabotage_app_configmap" {
  yaml_body = local.cabotage_app_configmap

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Vault/Consul Bootstrap ---

resource "null_resource" "cabotage_app_bootstrap" {
  triggers = {
    vault_bootstrap_id = null_resource.vault_bootstrap.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/cabotage-app-bootstrap.sh"
    environment = {
      SECRETS_DIR        = var.secrets_dir
      NAMESPACE          = kubernetes_namespace_v1.cabotage.metadata[0].name
      VAULT_POLICY_FILE  = "${path.module}/scripts/cabotage-app-policies/vault-policy.hcl"
      CONSUL_POLICY_FILE = "${path.module}/scripts/cabotage-app-policies/consul-policy.hcl"
      KUBE_CONTEXT       = var.kube_context
    }
  }

  depends_on = [
    null_resource.vault_bootstrap,
    null_resource.consul_bootstrap,
  ]
}

# --- GitHub App Secret ---

resource "null_resource" "cabotage_github_app_secret" {
  count = var.github_app_id != "" ? 1 : 0

  triggers = {
    app_id = var.github_app_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f "${var.secrets_dir}/github-app-private-key.pem" ] || [ ! -f "${var.secrets_dir}/github-webhook-secret" ]; then
        echo "GitHub App secret files not found in ${var.secrets_dir}, skipping."
        exit 0
      fi
      PRIVATE_KEY_B64=$(base64 < "${var.secrets_dir}/github-app-private-key.pem" | tr -d '\n')
      WEBHOOK_SECRET=$(cat "${var.secrets_dir}/github-webhook-secret" | tr -d '[:space:]')
      kubectl --context ${var.kube_context} create secret generic cabotage-github-app \
        --namespace ${kubernetes_namespace_v1.cabotage.metadata[0].name} \
        --from-literal=app-id="${var.github_app_id}" \
        --from-literal=private-key="$PRIVATE_KEY_B64" \
        --from-literal=webhook-secret="$WEBHOOK_SECRET" \
        --dry-run=client -o yaml | kubectl --context ${var.kube_context} apply -f -
    EOT
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Deployments ---

resource "kubectl_manifest" "cabotage_app_deployment_web" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-web.yml.tftpl", {
    image       = var.cabotage_app_image
    config_hash = local.cabotage_app_config_hash
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubectl_manifest.cabotage_app_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}

resource "kubectl_manifest" "cabotage_app_deployment_worker" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-worker.yml.tftpl", {
    image       = var.cabotage_app_image
    config_hash = local.cabotage_app_config_hash
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubectl_manifest.cabotage_app_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}

resource "kubectl_manifest" "cabotage_app_deployment_worker_beat" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-worker-beat.yml.tftpl", {
    image       = var.cabotage_app_image
    config_hash = local.cabotage_app_config_hash
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubectl_manifest.cabotage_app_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}

# --- Service ---

resource "kubectl_manifest" "cabotage_app_service" {
  yaml_body = file("${path.module}/manifests/cabotage-app/05-service.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Ingress ---

resource "kubectl_manifest" "cabotage_app_ingress" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/06-ingress.yml.tftpl", {
    hostname = var.cabotage_app_hostname
  })

  depends_on = [
    kubectl_manifest.cabotage_app_service,
    kubectl_manifest.nginx_ingress_class,
    helm_release.cert_manager,
  ]
}

# --- Post-deploy Configuration ---
# Patches configmap with DB URI, Redis URI, S3 credentials,
# restarts deployment, and runs DB migrations.

resource "null_resource" "cabotage_app_configure" {
  triggers = {
    deployment_id = kubectl_manifest.cabotage_app_deployment_web.id
    image         = var.cabotage_app_image
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/cabotage-app-configure.sh"
    environment = {
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    }
  }

  depends_on = [
    kubectl_manifest.cabotage_app_deployment_web,
    kubectl_manifest.postgres_cluster,
    kubectl_manifest.redis_cluster,
    null_resource.rustfs_create_buckets,
  ]
}
