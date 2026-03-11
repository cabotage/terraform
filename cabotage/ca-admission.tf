# --- CA Admission Webhook ---
# Step 5 in start-cluster
#
# Replaces: manifests/cabotage/ca-admission/
#
# Existing clusters — import before apply:
#
#   terraform import 'module.cabotage.kubernetes_service_account_v1.ca_admission' 'cabotage/cabotage-ca-admission'
#   terraform import 'module.cabotage.kubernetes_deployment_v1.ca_admission' 'cabotage/cabotage-ca-admission'
#   terraform import 'module.cabotage.kubernetes_service_v1.ca_admission' 'cabotage/cabotage-ca-admission'
#   terraform import 'module.cabotage.kubernetes_manifest.ca_admission_webhook' \
#     'apiVersion=admissionregistration.k8s.io/v1,kind=MutatingWebhookConfiguration,name=ca-admission.cabotage.io'

resource "kubernetes_service_account_v1" "ca_admission" {
  metadata {
    name      = "cabotage-ca-admission"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
  }

  automount_service_account_token = false
}

resource "kubernetes_deployment_v1" "ca_admission" {
  metadata {
    name      = "cabotage-ca-admission"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
    labels = {
      app = "cabotage-ca-admission"
    }
  }

  spec {
    replicas = var.ca_admission_replicas

    selector {
      match_labels = {
        app = "cabotage-ca-admission"
      }
    }

    template {
      metadata {
        labels = {
          app = "cabotage-ca-admission"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.ca_admission.metadata[0].name
        automount_service_account_token = false
        enable_service_links            = false

        security_context {
          run_as_non_root = true
          run_as_user     = 20000
          run_as_group    = 20000
          fs_group        = 20000
        }

        container {
          name              = "cabotage-ca-admission"
          image             = var.ca_admission_image
          image_pull_policy = "IfNotPresent"

          args = [
            "--bind=0.0.0.0:8443",
            "--certfile=/etc/tls/tls.crt",
            "--keyfile=/etc/tls/tls.key",
          ]

          port {
            container_port = 8443
            protocol       = "TCP"
          }

          resources {
            limits = {
              memory = "100Mi"
              cpu    = "100m"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            http_get {
              path   = "/_health"
              port   = 8443
              scheme = "HTTPS"
            }
          }

          readiness_probe {
            http_get {
              path   = "/_health"
              port   = 8443
              scheme = "HTTPS"
            }
            initial_delay_seconds = 5
            period_seconds        = 1
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/tls"
          }
        }

        volume {
          name = "tls"

          csi {
            driver    = "csi.cert-manager.io"
            read_only = true
            volume_attributes = {
              "csi.cert-manager.io/issuer-kind" = "ClusterIssuer"
              "csi.cert-manager.io/issuer-name" = "certificate-approver-ca-issuer"
              "csi.cert-manager.io/dns-names"   = "cabotage-ca-admission.cabotage.svc.cluster.local, cabotage-ca-admission.cabotage.svc.cluster, cabotage-ca-admission.cabotage.svc\n"
              "csi.cert-manager.io/duration"     = "9000h"
              "csi.cert-manager.io/fs-group"     = "20000"
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.cert_manager_csi_driver,
    kubectl_manifest.certificate_approver_ca_issuer,
  ]
}

resource "kubernetes_service_v1" "ca_admission" {
  metadata {
    name      = "cabotage-ca-admission"
    namespace = kubernetes_namespace_v1.cabotage.metadata[0].name
    labels = {
      app = "cabotage-ca-admission"
    }
  }

  spec {
    selector = {
      app = "cabotage-ca-admission"
    }

    port {
      port        = 443
      target_port = 8443
    }
  }
}

resource "kubectl_manifest" "ca_admission_webhook" {
  yaml_body = yamlencode({
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "MutatingWebhookConfiguration"
    metadata = {
      name = "ca-admission.cabotage.io"
      annotations = {
        "cert-manager.io/inject-ca-from" = "cert-manager/certificate-approver-ca"
      }
    }
    webhooks = [{
      name                    = "ca-admission.cabotage.io"
      admissionReviewVersions = ["v1"]
      sideEffects             = "None"
      failurePolicy           = "Fail"
      clientConfig = {
        service = {
          name      = "cabotage-ca-admission"
          namespace = "cabotage"
          path      = "/mutate"
        }
      }
      objectSelector = {
        matchLabels = {
          "ca-admission.cabotage.io" = "true"
        }
      }
      rules = [{
        apiGroups   = [""]
        apiVersions = ["v1"]
        operations  = ["CREATE"]
        resources   = ["pods"]
      }]
    }]
  })

  depends_on = [
    kubernetes_deployment_v1.ca_admission,
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
