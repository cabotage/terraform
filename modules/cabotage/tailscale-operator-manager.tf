# --- Tailscale ---
#
# Two components:
# 1. Tailscale operator (via Helm) — single cluster-wide operator
# 2. Tailscale operator manager (kopf) — provisions per-org Tailnet CRDs
#
# Gated behind var.enable_tailscale.

# --- Tailscale Operator (Helm) ---

# Create the tailscale namespace before the Secret and Helm release.
resource "kubernetes_namespace_v1" "tailscale" {
  count = var.enable_tailscale ? 1 : 0
  metadata { name = "tailscale" }
}

# Pre-create the OAuth Secret from files in secrets_dir.
# Uses a null_resource + kubectl so the secret value never enters terraform state.
resource "null_resource" "tailscale_operator_oauth" {
  count = var.enable_tailscale ? 1 : 0

  triggers = {
    namespace = "tailscale"
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl create secret generic operator-oauth \
        --namespace=tailscale \
        --from-file=client_id=${local.secrets_dir}/tailscale-oauth-client-id \
        --from-file=client_secret=${local.secrets_dir}/tailscale-oauth-client-secret \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }

  depends_on = [kubernetes_namespace_v1.tailscale]
}

resource "helm_release" "tailscale_operator" {
  count = var.enable_tailscale ? 1 : 0

  name      = "tailscale-operator"
  namespace = "tailscale"
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  version    = var.tailscale_operator_chart_version

  values = [yamlencode({
    operatorConfig = {
      image = {
        repository = var.tailscale_operator_image
        tag        = var.tailscale_operator_image_tag
      }
      defaultTags = ["tag:${var.tailscale_tag_prefix}-operator"]
    }
    proxyConfig = {
      image = {
        repository = var.tailscale_proxy_image
        tag        = var.tailscale_proxy_image_tag
      }
      defaultTags = "tag:${var.tailscale_tag_prefix}-operator"
    }
  })]

  # Strip the ProxyGroup CRD from the chart so Helm doesn't overwrite
  # our fork's version (which adds spec.tailnet for multi-tenant support).
  postrender = {
    binary_path = "${path.module}/scripts/helm-strip-proxygroup-crd.sh"
  }

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    null_resource.ca_admission_webhook_ready,
    kubectl_manifest.tailscale_tailnet_crd,
    kubectl_manifest.tailscale_proxygrouppolicy_crd,
    kubectl_manifest.tailscale_proxygroup_crd,
    null_resource.tailscale_operator_oauth,
  ]
}

# Supplemental RBAC for forked operator (Tailnet + ProxyGroupPolicy).
# REMOVE when upstream chart includes these resources.
resource "kubectl_manifest" "tailscale_operator_supplement_clusterrole" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator/00-clusterrole-supplement.yml")
}

resource "kubectl_manifest" "tailscale_operator_supplement_clusterrolebinding" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator/01-clusterrolebinding-supplement.yml")

  depends_on = [
    kubectl_manifest.tailscale_operator_supplement_clusterrole,
    helm_release.tailscale_operator,
  ]
}

# --- Operator Manager CRD ---

resource "kubectl_manifest" "tailscale_operator_manager_crd" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/00-crd.yml")
}

# Fork-only CRDs: Tailnet and ProxyGroupPolicy are not in upstream Helm chart
# (v1.94.2).  Applied BEFORE Helm so the operator can watch them at startup.
# Vendored from github.com/tailscale/tailscale at tag v1.96.3.
# REMOVE when upstream chart includes these CRDs.
resource "kubectl_manifest" "tailscale_tailnet_crd" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/crds/tailscale.com_tailnets.yaml")
}

resource "kubectl_manifest" "tailscale_proxygrouppolicy_crd" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/crds/tailscale.com_proxygrouppolicies.yaml")
}

# ProxyGroup CRD: upstream Helm chart ships this but WITHOUT the `tailnet`
# field our fork adds for multi-tenant support.  The postrender script on the
# Helm release strips the upstream ProxyGroup CRD so this version wins.
# REMOVE when upstream adds the tailnet field to ProxyGroup.
resource "kubectl_manifest" "tailscale_proxygroup_crd" {
  count             = var.enable_tailscale ? 1 : 0
  yaml_body         = file("${path.module}/manifests/tailscale-operator-manager/crds/tailscale.com_proxygroups.yaml")
  server_side_apply = true
  force_conflicts   = true
}

# --- ClusterKopfPeering ---

resource "kubectl_manifest" "tailscale_operator_manager_clusterpeering" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/00-clusterpeering.yml")

  depends_on = [kubectl_manifest.kopf_crd_clusterkopfpeering]
}

# --- RBAC for the manager ---

resource "kubectl_manifest" "tailscale_operator_manager_clusterrole" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/00-clusterrole.yml")
}

resource "kubectl_manifest" "tailscale_operator_manager_role" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/00-role.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "tailscale_operator_manager_serviceaccount" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/01-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "tailscale_operator_manager_clusterrolebinding" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/02-clusterrolebinding.yml")

  depends_on = [
    kubectl_manifest.tailscale_operator_manager_clusterrole,
    kubectl_manifest.tailscale_operator_manager_serviceaccount,
  ]
}

resource "kubectl_manifest" "tailscale_operator_manager_rolebinding" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/02-rolebinding.yml")

  depends_on = [
    kubectl_manifest.tailscale_operator_manager_role,
    kubectl_manifest.tailscale_operator_manager_serviceaccount,
  ]
}

# --- Manager Deployment ---

resource "kubectl_manifest" "tailscale_operator_manager_deployment" {
  count     = var.enable_tailscale ? 1 : 0
  yaml_body = file("${path.module}/manifests/tailscale-operator-manager/03-deployment.yml")

  depends_on = [
    kubectl_manifest.tailscale_operator_manager_clusterrolebinding,
    kubectl_manifest.tailscale_operator_manager_rolebinding,
    kubectl_manifest.tailscale_operator_manager_crd,
    kubectl_manifest.tailscale_operator_manager_clusterpeering,
    helm_release.tailscale_operator,
    null_resource.ca_admission_webhook_ready,
    null_resource.namespace_cleanup,
  ]
}
