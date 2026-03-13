# --- Consul ---
#
# Manifests live in manifests/consul/ — kept as close to the originals as
# possible. Only the ConfigMap and StatefulSet are templated (for datacenter,
# replicas, image, storage).

# --- Gossip Encryption Key ---

resource "random_id" "consul_gossip_key" {
  byte_length = 32
}

resource "kubernetes_secret_v1" "consul_gossip_key" {
  metadata {
    name      = "consul-gossip-key"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    key = random_id.consul_gossip_key.b64_std
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# --- Agent Token (placeholder until bootstrap) ---

resource "kubernetes_secret_v1" "consul_agent_token" {
  metadata {
    name      = "consul-agent-token"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  data = {
    token = "null"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

# --- Manifests ---

resource "kubectl_manifest" "consul_configmap" {
  yaml_body = templatefile("${path.module}/manifests/consul/02-configmap.yml.tftpl", {
    consul_datacenter = var.consul_datacenter
  })

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "consul_scripts_configmap" {
  yaml_body = file("${path.module}/manifests/consul/03-configmap.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "consul_statefulset" {
  yaml_body = templatefile("${path.module}/manifests/consul/04-statefulset.yml.tftpl", {
    replicas          = var.consul_replicas
    consul_image      = var.consul_image
    consul_datacenter = var.consul_datacenter
    consul_storage_size = var.consul_storage_size
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    null_resource.ca_admission_webhook_ready,
    null_resource.sign_intermediate_cas,
    kubectl_manifest.consul_configmap,
    kubectl_manifest.consul_scripts_configmap,
    kubernetes_secret_v1.consul_gossip_key,
    kubernetes_secret_v1.consul_agent_token,
  ]
}

resource "kubectl_manifest" "consul_pdb" {
  yaml_body = file("${path.module}/manifests/consul/05-poddisruptionbudget.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "consul_service_headless" {
  yaml_body = file("${path.module}/manifests/consul/06-service-headless.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "consul_service_ingress" {
  yaml_body = file("${path.module}/manifests/consul/06-service-ingress.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "consul_service_api" {
  yaml_body = file("${path.module}/manifests/consul/07-service-api.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}
