# --- Vault Bootstrap ---
#
# Runs locally via kubectl after the Vault cluster is ready. Initializes Vault,
# unseals all pods, enables auth backends, mounts secrets engines, and configures
# the internal PKI CA.
#
# Secrets stored locally in secrets_dir (never touch K8s):
#   - vault-bootstrap-token: root token
#   - vault-unseal-key: unseal key (manual unseal)
#   - vault-recovery-key: recovery key (auto-unseal)
#
# For production, use Shamir key shares with PGP encryption.

resource "null_resource" "vault_bootstrap" {
  triggers = {
    statefulset_id = kubectl_manifest.vault_statefulset.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/vault-bootstrap.sh"
    environment = {
      SECRETS_DIR           = local.secrets_dir
      CA_CERT_FILE          = local.ca_cert_file
      NAMESPACE             = kubernetes_namespace_v1.cabotage.metadata[0].name
      VAULT_REPLICAS        = tostring(var.vault_replicas)
      KUBE_CONTEXT          = var.kube_context
      VAULT_AUTO_UNSEAL     = var.vault_auto_unseal_kms_key_id != "" ? "true" : "false"
      VAULT_DEV_AUTO_UNSEAL = var.vault_dev_auto_unseal ? "true" : "false"
    }
  }

  depends_on = [
    kubectl_manifest.vault_statefulset,
    null_resource.consul_bootstrap,
  ]
}
