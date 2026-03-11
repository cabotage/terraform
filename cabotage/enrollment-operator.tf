# --- Kopf CRDs + Enrollment Operator ---
#
# Manifests live in manifests/kopf/ and manifests/enrollment-operator/.
# The bootstrap script configures vault policies and consul roles.

# --- Kopf CRDs ---

resource "kubectl_manifest" "kopf_crd_clusterkopfpeering" {
  yaml_body = file("${path.module}/manifests/kopf/00-crd-clusterkopfpeering.yml")
}

resource "kubectl_manifest" "kopf_crd_kopfpeering" {
  yaml_body = file("${path.module}/manifests/kopf/00-crd-kopfpeering.yml")
}

# --- Default Peerings ---

resource "kubectl_manifest" "kopf_default_clusterpeering" {
  yaml_body = file("${path.module}/manifests/kopf/01-default-clusterpeering.yml")

  depends_on = [kubectl_manifest.kopf_crd_clusterkopfpeering]
}

resource "kubectl_manifest" "kopf_default_peering" {
  yaml_body = file("${path.module}/manifests/kopf/01-default-peering.yml")

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    kubectl_manifest.kopf_crd_kopfpeering,
  ]
}

# --- Enrollment Operator CRD ---

resource "kubectl_manifest" "enrollment_operator_crd" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/00-crd.yml")
}

# --- Enrollment Operator ClusterKopfPeering ---

resource "kubectl_manifest" "enrollment_operator_clusterpeering" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/00-clusterpeering.yml")

  depends_on = [kubectl_manifest.kopf_crd_clusterkopfpeering]
}

# --- Enrollment Operator RBAC ---

resource "kubectl_manifest" "enrollment_operator_role" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/00-role.yml")
}

resource "kubectl_manifest" "enrollment_operator_serviceaccount" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/01-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "enrollment_operator_rolebinding" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/02-rolebinding.yml")

  depends_on = [
    kubectl_manifest.enrollment_operator_role,
    kubectl_manifest.enrollment_operator_serviceaccount,
  ]
}

# --- Vault/Consul Bootstrap for Enrollment Operator ---

resource "null_resource" "enrollment_operator_bootstrap" {
  triggers = {
    vault_bootstrap_id = null_resource.vault_bootstrap.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/enrollment-operator-bootstrap.sh"
    environment = {
      SECRETS_DIR = var.secrets_dir
      NAMESPACE   = kubernetes_namespace_v1.cabotage.metadata[0].name
      POLICY_FILE = "${path.module}/scripts/enrollment-operator-policy.hcl"
    }
  }

  depends_on = [
    null_resource.vault_bootstrap,
    null_resource.consul_bootstrap,
  ]
}

# --- Enrollment Operator Deployment ---

resource "kubectl_manifest" "enrollment_operator_deployment" {
  yaml_body = file("${path.module}/manifests/enrollment-operator/03-deployment.yml")

  depends_on = [
    kubectl_manifest.enrollment_operator_rolebinding,
    kubectl_manifest.enrollment_operator_crd,
    kubectl_manifest.enrollment_operator_clusterpeering,
    null_resource.enrollment_operator_bootstrap,
    null_resource.ca_admission_webhook_ready,
  ]
}
