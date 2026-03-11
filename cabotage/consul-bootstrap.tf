# --- Consul ACL Bootstrap Job ---
#
# Runs once after the Consul cluster is ready. Bootstraps ACLs, creates
# policies (anonymous, agent, vault), creates tokens, and stores them
# in Kubernetes secrets.
#
# The management token is stored in the consul-management-token secret.
# On existing clusters where ACLs are already bootstrapped, the job
# detects this and skips the bootstrap step — but it still needs the
# management token in the secret to create/verify policies and tokens.
#
# For existing clusters, create the management token secret before import:
#
#   kubectl create secret generic consul-management-token \
#     -n cabotage --from-literal=token=<your-management-token>
#
# Then import:
#
#   terraform import 'module.cabotage.kubernetes_secret_v1.consul_management_token' 'cabotage/consul-management-token'
#   terraform import 'module.cabotage.kubernetes_secret_v1.vault_consul_token' 'cabotage/vault-consul-token'
#   terraform import 'module.cabotage.kubernetes_service_account_v1.consul_bootstrap' 'cabotage/consul-bootstrap'
#   terraform import 'module.cabotage.kubernetes_role_v1.consul_bootstrap' 'cabotage/consul-bootstrap'
#   terraform import 'module.cabotage.kubernetes_role_binding_v1.consul_bootstrap' 'cabotage/consul-bootstrap'
#   terraform import 'module.cabotage.kubernetes_config_map_v1.consul_bootstrap' 'cabotage/consul-bootstrap'

# --- Secrets for bootstrap outputs ---

resource "kubernetes_secret_v1" "consul_management_token" {
  metadata {
    name      = "consul-management-token"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    token = "null"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_secret_v1" "vault_consul_token" {
  metadata {
    name      = "vault-consul-token"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    token = "null"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# --- RBAC for bootstrap job ---

resource "kubernetes_service_account_v1" "consul_bootstrap" {
  metadata {
    name      = "consul-bootstrap"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }
}

resource "kubernetes_role_v1" "consul_bootstrap" {
  metadata {
    name      = "consul-bootstrap"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = ["consul-management-token", "consul-agent-token", "vault-consul-token"]
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "consul_bootstrap" {
  metadata {
    name      = "consul-bootstrap"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.consul_bootstrap.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.consul_bootstrap.metadata[0].name
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }
}

# --- Bootstrap script ---

resource "kubernetes_config_map_v1" "consul_bootstrap" {
  metadata {
    name      = "consul-bootstrap"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    "bootstrap.sh" = file("${path.module}/scripts/consul-bootstrap.sh")
  }
}

# --- Bootstrap Job (run once) ---
#
# Uses null_resource so the job only runs once when the StatefulSet is
# first created. Subsequent applies are no-ops.

resource "null_resource" "consul_bootstrap" {
  triggers = {
    statefulset_uid = kubernetes_stateful_set_v1.consul.metadata[0].uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -n cabotage -f - <<'EOF'
      apiVersion: batch/v1
      kind: Job
      metadata:
        name: consul-bootstrap
        namespace: cabotage
      spec:
        backoffLimit: 4
        template:
          metadata:
            labels:
              app: consul-bootstrap
          spec:
            serviceAccountName: consul-bootstrap
            restartPolicy: OnFailure
            securityContext:
              runAsNonRoot: true
              runAsUser: 20000
              runAsGroup: 20000
            containers:
              - name: bootstrap
                image: curlimages/curl:8.5.0
                command: ["/bin/sh", "/scripts/bootstrap.sh"]
                volumeMounts:
                  - name: scripts
                    mountPath: /scripts
            volumes:
              - name: scripts
                configMap:
                  name: consul-bootstrap
      EOF
      kubectl wait -n cabotage --for=condition=complete job/consul-bootstrap --timeout=5m
    EOT
  }

  depends_on = [
    kubernetes_stateful_set_v1.consul,
    kubernetes_config_map_v1.consul_bootstrap,
    kubernetes_service_account_v1.consul_bootstrap,
    kubernetes_role_binding_v1.consul_bootstrap,
    kubernetes_secret_v1.consul_management_token,
  ]
}
