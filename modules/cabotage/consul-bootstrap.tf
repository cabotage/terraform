# --- Consul ACL Bootstrap ---
#
# Runs locally via kubectl after the Consul cluster is ready. Bootstraps ACLs,
# creates policies (anonymous, agent, vault), and stores tokens:
#   - Management token: local file in secrets_dir (never touches K8s)
#   - Agent token: K8s secret (pods need it at runtime)
#   - Vault consul token: K8s secret (vault pods need it at runtime)

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

resource "null_resource" "consul_bootstrap" {
  triggers = {
    statefulset_id = kubectl_manifest.consul_statefulset.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/consul-bootstrap.sh"
    environment = {
      SECRETS_DIR     = local.secrets_dir
      NAMESPACE       = kubernetes_namespace_v1.cabotage.metadata[0].name
      CONSUL_REPLICAS    = tostring(var.consul_replicas)
      KUBE_CONTEXT       = var.kube_context
      CONSUL_LOCAL_PORT  = tostring(var.consul_local_port)
    }
  }

  depends_on = [
    kubectl_manifest.consul_statefulset,
    kubernetes_secret_v1.consul_agent_token,
    kubernetes_secret_v1.vault_consul_token,
  ]
}
