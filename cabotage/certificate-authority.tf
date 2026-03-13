# --- Certificate Authorities ---
#
# Root CA is generated locally (never enters K8s). Intermediate CAs are
# created by cert-manager (key generation), then signed locally with the
# root CA key and patched back into the K8s secrets.
#
# Local files:
#   ca_cert_file — root CA certificate (public, safe to commit)
#   secrets_dir/ca.key — root CA private key

locals {
  # Extract short name from ARN or use as-is (e.g. "arn:aws:eks:...:cluster/dev-astral" -> "dev-astral")
  cluster_short_name = element(split("/", var.cluster_identifier), length(split("/", var.cluster_identifier)) - 1)
}

# --- Root CA (local) ---

resource "null_resource" "root_ca" {
  triggers = {
    cluster_id = var.cluster_identifier
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/bootstrap-root-ca.sh"
    environment = {
      SECRETS_DIR  = var.secrets_dir
      CA_CERT_FILE = var.ca_cert_file
      CLUSTER_ID   = var.cluster_identifier
      KUBE_CONTEXT = var.kube_context
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_namespace_v1.cabotage,
  ]
}

# --- SelfSigned issuer (bootstraps intermediate key generation) ---

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

# --- Intermediate CA Certificates ---

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
      commonName = "${local.cluster_short_name} Certificate Approver Intermediate CA"
      secretName = "certificate-approver-ca-key-pair"
      duration   = "43800h0m0s" # 5 years
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
      commonName = "${local.cluster_short_name} Operators Intermediate CA"
      secretName = "operators-ca-key-pair"
      duration   = "43800h0m0s" # 5 years
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

# --- Sign intermediates with local root CA ---

resource "null_resource" "sign_intermediate_cas" {
  triggers = {
    cert_approver_id = kubectl_manifest.certificate_approver_ca_certificate.id
    operators_id     = kubectl_manifest.operators_ca_certificate.id
  }

  provisioner "local-exec" {
    command = "sh ${path.module}/scripts/sign-intermediate-cas.sh"
    environment = {
      SECRETS_DIR  = var.secrets_dir
      CA_CERT_FILE = var.ca_cert_file
      CLUSTER_ID   = var.cluster_identifier
      KUBE_CONTEXT = var.kube_context
    }
  }

  depends_on = [
    null_resource.root_ca,
    kubectl_manifest.certificate_approver_ca_certificate,
    kubectl_manifest.operators_ca_certificate,
  ]
}

# --- ClusterIssuers ---

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

  depends_on = [null_resource.sign_intermediate_cas]
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

  depends_on = [null_resource.sign_intermediate_cas]
}
