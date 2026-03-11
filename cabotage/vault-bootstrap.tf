# --- Vault Bootstrap ---
#
# Runs locally via kubectl after the Vault cluster is ready. Initializes Vault,
# unseals all pods, enables auth backends, mounts secrets engines, and configures
# the internal PKI CA.
#
# Secrets stored locally in secrets_dir (never touch K8s):
#   - vault-bootstrap-token: root token
#   - vault-unseal-key: unseal key
#
# For production, use Shamir key shares with PGP encryption.

resource "null_resource" "vault_bootstrap" {
  triggers = {
    statefulset_id = kubectl_manifest.vault_statefulset.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/vault-bootstrap.sh"
    environment = {
      SECRETS_DIR    = var.secrets_dir
      NAMESPACE      = kubernetes_namespace_v1.cabotage.metadata[0].name
      VAULT_REPLICAS = tostring(var.vault_replicas)
    }
  }

  depends_on = [
    kubectl_manifest.vault_statefulset,
    null_resource.consul_bootstrap,
  ]
}
