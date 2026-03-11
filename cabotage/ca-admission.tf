# --- CA Admission Webhook ---
#
# Manifests live in manifests/ca-admission/ — kept as close to the originals
# as possible. Only the Deployment is templated (for image and replicas).

resource "kubectl_manifest" "ca_admission_role" {
  yaml_body = file("${path.module}/manifests/ca-admission/00-role.yml")
}

resource "kubectl_manifest" "ca_admission_serviceaccount" {
  yaml_body = file("${path.module}/manifests/ca-admission/00-serviceaccount.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "ca_admission_clusterrolebinding" {
  yaml_body = file("${path.module}/manifests/ca-admission/01-clusterrolebinding.yml")

  depends_on = [
    kubectl_manifest.ca_admission_role,
    kubectl_manifest.ca_admission_serviceaccount,
  ]
}

resource "kubectl_manifest" "ca_admission_deployment" {
  yaml_body = templatefile("${path.module}/manifests/ca-admission/02-deployment.yml.tftpl", {
    replicas = var.ca_admission_replicas
    image    = var.ca_admission_image
  })

  depends_on = [
    kubernetes_namespace_v1.cabotage,
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
    kubectl_manifest.ca_admission_serviceaccount,
  ]
}

resource "kubectl_manifest" "ca_admission_service" {
  yaml_body = file("${path.module}/manifests/ca-admission/03-service.yml")

  depends_on = [kubernetes_namespace_v1.cabotage]
}

resource "kubectl_manifest" "ca_admission_webhook" {
  yaml_body = file("${path.module}/manifests/ca-admission/04-webhook.yml")

  depends_on = [
    kubectl_manifest.ca_admission_deployment,
    null_resource.sign_intermediate_cas,
  ]
}

resource "null_resource" "ca_admission_webhook_ready" {
  triggers = {
    webhook_id = kubectl_manifest.ca_admission_webhook.id
    signing_id = null_resource.sign_intermediate_cas.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for caBundle injection on ca-admission webhook..."
      for i in $(seq 1 60); do
        bundle=$(kubectl get mutatingwebhookconfiguration ca-admission.cabotage.io -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null)
        if [ -n "$bundle" ]; then
          echo "caBundle injected."
          exit 0
        fi
        sleep 2
      done
      echo "Timed out waiting for caBundle injection."
      exit 1
    EOT
  }
}
