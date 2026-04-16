# --- Cabotage Application ---
# Step 14 in start-cluster
#
# Manifests live in manifests/cabotage-app/.
# Bootstrap script configures vault policy, consul policy, transit backend.
# Configure script patches DB/Redis/S3 URIs and runs DB migrations.

locals {
  cabotage_app_config_data = merge({
    CABOTAGE_CLUSTER_INTERNAL_CIDRS                 = join(",", var.cluster_internal_cidrs)
    CABOTAGE_CONSUL_HOST                            = "consul.cabotage.svc.cluster.local"
    CABOTAGE_CONSUL_PORT                            = "8443"
    CABOTAGE_CONSUL_PREFIX                          = "cabotage"
    CABOTAGE_CONSUL_SCHEME                          = "https"
    CABOTAGE_CONSUL_TOKEN_FILE                      = "/var/run/secrets/vault/consul-token"
    CABOTAGE_CONSUL_VERIFY                          = "/var/run/secrets/cabotage.io/ca.crt"
    CABOTAGE_EXT_PREFERRED_URL_SCHEME               = "https"
    CABOTAGE_EXT_SERVER_NAME                        = var.cabotage_app_hostname
    CABOTAGE_GITHUB_OAUTH_ALLOWED_ORGS              = var.github_oauth_allowed_orgs
    CABOTAGE_GITHUB_OAUTH_ONLY                      = var.github_oauth_only ? "True" : "False"
    CABOTAGE_INGRESS_DOMAIN                         = var.cabotage_ingress_domain
    CABOTAGE_KUBERNETES_ENABLED                     = "True"
    CABOTAGE_LOKI_URL                               = "https://resident-loki-read.cabotage.svc.cluster.local:3100"
    CABOTAGE_LOKI_VERIFY                            = "/var/run/secrets/cabotage.io/ca.crt"
    CABOTAGE_MIMIR_URL                              = "https://resident-mimir-read.cabotage.svc.cluster.local:8080"
    CABOTAGE_MIMIR_VERIFY                           = "/var/run/secrets/cabotage.io/ca.crt"
    CABOTAGE_ALERTMANAGER_URL                       = "https://resident-mimir-backend.cabotage.svc.cluster.local:8080/alertmanager"
    CABOTAGE_ALERTMANAGER_VERIFY                    = "/var/run/secrets/cabotage.io/ca.crt"
    CABOTAGE_NETWORK_POLICIES_ENABLED               = "True"
    CABOTAGE_OMNIBUS_BUILDS                         = "True"
    CABOTAGE_PROXY_FIX_NUM_PROXIES                  = tostring(var.proxy_fix_num_proxies)
    CABOTAGE_REGISTRY                               = "registry.${var.cabotage_ingress_domain}"
    CABOTAGE_REGISTRY_BUILD                         = "registry.${var.cabotage_ingress_domain}"
    CABOTAGE_REGISTRY_PULL                          = "registry.${var.cabotage_ingress_domain}"
    CABOTAGE_REGISTRY_SECURE                        = "True"
    CABOTAGE_REGISTRY_VERIFY                        = var.registry_verify
    CABOTAGE_REQUIRE_MFA                            = var.require_mfa ? "True" : "False"
    CABOTAGE_SECURITY_CONFIRMABLE                   = var.security_confirmable ? "True" : "False"
    CABOTAGE_SECURITY_MULTI_FACTOR_RECOVERY_CODES_N = tostring(var.security_multi_factor_recovery_codes_n)
    CABOTAGE_SECURITY_TOTP_ISSUER                   = var.security_totp_issuer
    CABOTAGE_SECURITY_TWO_FACTOR_ALWAYS_VALIDATE    = var.security_two_factor_always_validate ? "True" : "False"
    CABOTAGE_SECURITY_TWO_FACTOR_LOGIN_VALIDITY     = var.security_two_factor_login_validity
    CABOTAGE_SHELLZ_ENABLED                         = "True"
    CABOTAGE_SIDECAR_IMAGE                          = "ghcr.io/cabotage/containers/sidecar-rs:1.1a1"
    CABOTAGE_TAILSCALE_OPERATOR_ENABLED             = var.enable_tailscale ? "True" : "False"
    CABOTAGE_TAILSCALE_TAG_PREFIX                   = var.tailscale_tag_prefix
    CABOTAGE_VAULT_LEASE_PATH                       = "/var/run/secrets/vault"
    CABOTAGE_VAULT_PREFIX                           = "cabotage-secrets"
    CABOTAGE_VAULT_SIGNING_KEY                      = "registry"
    CABOTAGE_VAULT_SIGNING_MOUNT                    = "cabotage-app-transit"
    CABOTAGE_VAULT_TOKEN_FILE                       = "/var/run/secrets/vault/vault-token"
    CABOTAGE_VAULT_URL                              = "https://vault.cabotage.svc.cluster.local"
    CABOTAGE_VAULT_VERIFY                           = "/var/run/secrets/cabotage.io/ca.crt"
    FLASK_APP                                       = "cabotage.server.wsgi"
    SENTRY_ENVIRONMENT                              = var.sentry_environment
    }, var.enable_karpenter ? {
    CABOTAGE_BACKING_SERVICES_POOL = var.karpenter_backing_services_pool_name
    CABOTAGE_PREVIEW_POOL          = var.karpenter_preview_pool_name
    CABOTAGE_STANDARD_POOL         = var.karpenter_standard_pool_name
  } : {})
  cabotage_app_config_hash = sha256(jsonencode(local.cabotage_app_config_data))
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

resource "kubernetes_config_map_v1" "cabotage_app_configmap" {
  metadata {
    name      = "cabotage-config"
    namespace = "cabotage"
  }

  data = local.cabotage_app_config_data

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Rollout restart on any configmap change (including drift correction) ---

resource "null_resource" "cabotage_app_configmap_rollout" {
  lifecycle {
    replace_triggered_by = [kubernetes_config_map_v1.cabotage_app_configmap]
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context ${var.kube_context} rollout restart -n cabotage deployment/cabotage-app-web deployment/cabotage-app-worker deployment/cabotage-app-worker-beat
      kubectl --context ${var.kube_context} rollout status -n cabotage deployment/cabotage-app-web --timeout=300s
      kubectl --context ${var.kube_context} rollout status -n cabotage deployment/cabotage-app-worker --timeout=300s
      kubectl --context ${var.kube_context} rollout status -n cabotage deployment/cabotage-app-worker-beat --timeout=300s
    EOT
  }

  depends_on = [
    kubectl_manifest.cabotage_app_deployment_web,
    kubectl_manifest.cabotage_app_deployment_worker,
    kubectl_manifest.cabotage_app_deployment_worker_beat,
    null_resource.cabotage_app_configure,
  ]
}

# --- Vault/Consul Bootstrap ---

resource "null_resource" "cabotage_app_bootstrap" {
  triggers = {
    vault_bootstrap_id = null_resource.vault_bootstrap.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/cabotage-app-bootstrap.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR        = local.secrets_dir
      NAMESPACE          = kubernetes_namespace_v1.cabotage.metadata[0].name
      VAULT_POLICY_FILE  = "${path.module}/scripts/cabotage-app-policies/vault-policy.hcl"
      CONSUL_POLICY_FILE = "${path.module}/scripts/cabotage-app-policies/consul-policy.hcl"
      KUBE_CONTEXT       = var.kube_context
    })
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
    command = "sh ${path.module}/scripts/create-github-app-secret.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR   = local.secrets_dir
      NAMESPACE     = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT  = var.kube_context
      GITHUB_APP_ID = var.github_app_id
    })
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- DockerHub Credentials Secret ---

moved {
  from = null_resource.cabotage_dockerhub_secret[0]
  to   = null_resource.cabotage_dockerhub_secret
}

resource "null_resource" "cabotage_dockerhub_secret" {
  triggers = {
    secret_name = "cabotage-dockerhub"
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/create-dockerhub-secret.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR  = local.secrets_dir
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    })
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Notifications Slack Secret ---

resource "null_resource" "cabotage_notifications_slack_secret" {
  triggers = {
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/create-slack-secret.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR  = local.secrets_dir
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    })
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Notifications Discord Secret ---

resource "null_resource" "cabotage_notifications_discord_secret" {
  triggers = {
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/create-discord-secret.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR  = local.secrets_dir
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    })
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Sentry Secret ---

resource "null_resource" "cabotage_sentry_secret" {
  triggers = {
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/create-sentry-secret.sh"
    environment = merge(local.secrets_manager_env, {
      SECRETS_DIR  = local.secrets_dir
      NAMESPACE    = kubernetes_namespace_v1.cabotage.metadata[0].name
      KUBE_CONTEXT = var.kube_context
    })
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Alertmanager Webhook Secret ---

resource "random_password" "alertmanager_webhook_secret" {
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "alertmanager_webhook" {
  metadata {
    name      = "cabotage-alertmanager-webhook"
    namespace = "cabotage"
  }

  data = {
    secret = random_password.alertmanager_webhook_secret.result
  }

  lifecycle {
    ignore_changes = [data]
  }

  depends_on = [kubernetes_namespace_v1.cabotage]
}

# --- Deployments ---

resource "kubectl_manifest" "cabotage_app_deployment_web" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-web.yml.tftpl", {
    image                 = var.cabotage_app_image
    config_hash           = local.cabotage_app_config_hash
    use_s3                = local.use_s3
    replicas              = var.cabotage_app_web_replicas
    resources             = var.cabotage_app_web_resources
    sidecar_resources     = var.cabotage_sidecar_resources
    sidecar_tls_resources = var.cabotage_sidecar_tls_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubernetes_config_map_v1.cabotage_app_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}

resource "kubectl_manifest" "cabotage_app_deployment_worker" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-worker.yml.tftpl", {
    image             = var.cabotage_app_image
    config_hash       = local.cabotage_app_config_hash
    use_s3            = local.use_s3
    replicas          = var.cabotage_app_worker_replicas
    resources         = var.cabotage_app_worker_resources
    sidecar_resources = var.cabotage_sidecar_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubernetes_config_map_v1.cabotage_app_configmap,
    null_resource.cabotage_app_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}

resource "kubectl_manifest" "cabotage_app_deployment_worker_beat" {
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/04-deployment-worker-beat.yml.tftpl", {
    image             = var.cabotage_app_image
    config_hash       = local.cabotage_app_config_hash
    use_s3            = local.use_s3
    resources         = var.cabotage_app_worker_beat_resources
    sidecar_resources = var.cabotage_sidecar_resources
  })

  wait_for_rollout = false

  depends_on = [
    kubectl_manifest.cabotage_app_rolebinding,
    null_resource.cabotage_app_enrollment_ready,
    kubernetes_config_map_v1.cabotage_app_configmap,
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

resource "kubectl_manifest" "cabotage_app_ingress_funnel" {
  count = var.enable_tailscale && var.enable_tailscale_ingress ? 1 : 0
  yaml_body = templatefile("${path.module}/manifests/cabotage-app/05-ingress-funnel.yml.tftpl", {
    hostname = var.cabotage_tailscale_hostname
  })

  depends_on = [
    kubectl_manifest.cabotage_app_service,
    helm_release.tailscale_operator,
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
