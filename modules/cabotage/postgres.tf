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

# --- CNPG Cluster ---

resource "kubectl_manifest" "postgres_cluster" {
  yaml_body = file("${path.module}/manifests/postgres/01-cluster.yml")

  wait_for_rollout = false

  depends_on = [
    helm_release.cnpg,
    kubectl_manifest.postgres_certificate,
    null_resource.postgres_ca_secret,
  ]
}
