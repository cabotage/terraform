# --- Postgres (CNPG Cluster) ---
# Step 12 in start-cluster
#
# Manifests live in manifests/postgres/.
# The CNPG operator is installed via Helm in cnpg.tf.
# The operators-ca-crt CA secret must be copied from cert-manager to postgres.

# --- Namespace ---

resource "kubernetes_namespace_v1" "postgres" {
  metadata {
    name = "postgres"
  }
}

# --- Copy CA cert to postgres namespace ---

resource "null_resource" "postgres_ca_secret" {
  triggers = {
    signing_id = null_resource.sign_intermediate_cas.id
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = <<-EOT
      echo "Copying operators-ca-crt to postgres namespace..."
      for i in $(seq 1 10); do
        if kubectl --context $KUBE_CONTEXT get -n cert-manager secret operators-ca-crt -o json \
          | jq '{apiVersion, kind, type, data} + {metadata: {name: .metadata.name, namespace: "postgres"}}' \
          | kubectl --context $KUBE_CONTEXT apply -f -; then
          echo "Done."
          exit 0
        fi
        echo "  Attempt $i failed, retrying in 5s..."
        sleep 5
      done
      echo "ERROR: Failed to copy operators-ca-crt to postgres namespace"
      exit 1
    EOT
  }

  depends_on = [
    null_resource.sign_intermediate_cas,
    kubernetes_namespace_v1.postgres,
  ]
}

# --- TLS Certificate ---

resource "kubectl_manifest" "postgres_tls_secret" {
  yaml_body = file("${path.module}/manifests/postgres/00-secret-tls.yml")

  depends_on = [kubernetes_namespace_v1.postgres]
}

resource "kubectl_manifest" "postgres_certificate" {
  yaml_body = file("${path.module}/manifests/postgres/00-certificate.yml")

  depends_on = [
    kubernetes_namespace_v1.postgres,
    kubectl_manifest.operators_ca_issuer,
    null_resource.sign_intermediate_cas,
    kubectl_manifest.postgres_tls_secret,
  ]
}

# --- Wait for CNPG webhook to be ready ---

resource "null_resource" "cnpg_webhook_ready" {
  triggers = {
    cnpg_id = helm_release.cnpg.id
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = <<-EOT
      echo "Waiting for CNPG webhook to be ready..."
      for i in $(seq 1 60); do
        if kubectl --context $KUBE_CONTEXT get endpoints cnpg-webhook-service -n postgres -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
          echo "CNPG webhook is ready."
          exit 0
        fi
        echo "  Attempt $i/60, retrying in 5s..."
        sleep 5
      done
      echo "ERROR: CNPG webhook not ready after 300s"
      exit 1
    EOT
  }

  depends_on = [helm_release.cnpg]
}

# --- CNPG Cluster ---

resource "kubectl_manifest" "postgres_cluster" {
  yaml_body = templatefile("${path.module}/manifests/postgres/01-cluster.yml", {
    storage_size = var.cabotage_postgres_storage_size
    instances    = var.cabotage_postgres_instances
    resources    = var.cabotage_postgres_resources
    parameters   = var.cabotage_postgres_parameters
  })

  wait_for_rollout = false

  depends_on = [
    null_resource.cnpg_webhook_ready,
    kubectl_manifest.postgres_certificate,
    null_resource.postgres_ca_secret,
  ]
}
