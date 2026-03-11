# --- Vault ---
#
# Deploys a Vault cluster using Consul as its storage backend.
# Each Vault pod runs a Consul client agent sidecar.
#
# Manifests live in manifests/vault/ — kept as close to the originals as
# possible. Only the StatefulSet is templated (for replicas, images, datacenter).

resource "kubectl_manifest" "vault_serviceaccount" {
  yaml_body = file("${path.module}/manifests/vault/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "vault_clusterrolebinding" {
  yaml_body = file("${path.module}/manifests/vault/02-clusterrolebinding.yml")
}

resource "kubectl_manifest" "vault_configmap" {
  yaml_body = file("${path.module}/manifests/vault/03-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "vault_statefulset" {
  yaml_body = templatefile("${path.module}/manifests/vault/04-statefulset.yml.tftpl", {
    replicas          = var.vault_replicas
    vault_image       = var.vault_image
    consul_image      = var.consul_image
    consul_datacenter = var.consul_datacenter
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
    null_resource.consul_bootstrap,
    kubectl_manifest.vault_serviceaccount,
    kubectl_manifest.vault_configmap,
  ]
}

resource "kubectl_manifest" "vault_pdb" {
  yaml_body = file("${path.module}/manifests/vault/05-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "vault_service" {
  yaml_body = file("${path.module}/manifests/vault/05-service.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}
