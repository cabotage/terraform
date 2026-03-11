# --- Certificate Authorities ---
# Step 4 in start-cluster
#
# A SelfSigned ClusterIssuer bootstraps the root CA. The root CA signs two
# intermediate CAs (certificate-approver, operators). cert-manager generates
# and stores all key pairs as Kubernetes secrets — they never enter Terraform
# state.
#
# New clusters: terraform apply creates everything from scratch.
#
# Existing clusters (migrating from cfssl bootstrap scripts):
#
#   1. Create the root CA secret from your existing key material:
#
#        kubectl create secret tls cabotage-root-ca-key-pair \
#          -n cert-manager --cert=ca.crt --key=ca.key
#
#      The intermediate secrets (certificate-approver-ca-key-pair,
#      operators-ca-key-pair) should already exist in cert-manager namespace.
#      cert-manager will adopt them without regenerating keys.
#
#   2. Import existing resources into Terraform state:
#
#        terraform import 'module.cabotage.kubectl_manifest.certificate_approver_ca_issuer' \
#          'cert-manager.io/v1//ClusterIssuer//certificate-approver-ca-issuer'
#        terraform import 'module.cabotage.kubectl_manifest.operators_ca_issuer' \
#          'cert-manager.io/v1//ClusterIssuer//operators-ca-issuer'
#        terraform import 'module.cabotage.kubernetes_config_map_v1.cabotage_ca' \
#          'cabotage/cabotage-ca'
#        terraform import 'module.cabotage.kubernetes_config_map_v1.cabotage_ca_default' \
#          'default/cabotage-ca'
#
#   3. terraform apply — creates the SelfSigned issuer, root CA Certificate,
#      root CA ClusterIssuer, and intermediate CA Certificate resources.
#      cert-manager sees the existing secrets and does not regenerate them.

# Bootstrap issuer for generating the root CA
resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned"
    }
    spec = {
      selfSigned = {}
    }
  })

  depends_on = [helm_release.cert_manager]
}

# --- Root CA ---

resource "kubectl_manifest" "root_ca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "cabotage-root-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA       = true
      commonName = "${var.cluster_identifier} Cabotage Root CA"
      secretName = "cabotage-root-ca-key-pair"
      duration   = "87600h0m0s" # 10 years
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = "selfsigned"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.selfsigned_issuer]
}

# Root CA issuer — signs the intermediates
resource "kubectl_manifest" "root_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "cabotage-root-ca"
    }
    spec = {
      ca = {
        secretName = "cabotage-root-ca-key-pair"
      }
    }
  })

  depends_on = [kubectl_manifest.root_ca_certificate]
}

# Publish root CA cert as ConfigMaps in cabotage and default namespaces.
# Uses a provisioner because the root CA secret is created by cert-manager
# during apply and isn't available at plan time.
resource "null_resource" "cabotage_ca_configmaps" {
  triggers = {
    root_ca_id = kubectl_manifest.root_ca_certificate.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      CA_CRT=$(kubectl get secret -n cert-manager cabotage-root-ca-key-pair -o jsonpath='{.data.tls\.crt}' | base64 -d)
      for ns in cabotage default; do
        kubectl create configmap cabotage-ca -n "$ns" --from-literal="ca.crt=$CA_CRT" --dry-run=client -o yaml | kubectl apply -f -
      done
    EOT
  }

  depends_on = [kubectl_manifest.root_ca_certificate]
}

# --- Certificate Approver Intermediate CA ---

resource "kubectl_manifest" "certificate_approver_ca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "certificate-approver-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA       = true
      commonName = "${var.cluster_identifier} Certificate Approver Intermediate CA"
      secretName = "certificate-approver-ca-key-pair"
      duration   = "43800h0m0s" # 5 years
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = "cabotage-root-ca"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.root_ca_issuer]
}

resource "kubectl_manifest" "certificate_approver_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "certificate-approver-ca-issuer"
    }
    spec = {
      ca = {
        secretName = "certificate-approver-ca-key-pair"
      }
    }
  })

  depends_on = [kubectl_manifest.certificate_approver_ca_certificate]
}

# --- Operators Intermediate CA ---

resource "kubectl_manifest" "operators_ca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "operators-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA       = true
      commonName = "${var.cluster_identifier} Operators Intermediate CA"
      secretName = "operators-ca-key-pair"
      duration   = "43800h0m0s" # 5 years
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = "cabotage-root-ca"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.root_ca_issuer]
}

resource "kubectl_manifest" "operators_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "operators-ca-issuer"
    }
    spec = {
      ca = {
        secretName = "operators-ca-key-pair"
      }
    }
  })

  depends_on = [kubectl_manifest.operators_ca_certificate]
}
