# --- cert-manager + CSI Driver ---
# Step 3 in start-cluster

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_chart_version

  values = [yamlencode({
    installCRDs  = true
    featureGates = "ExperimentalCertificateSigningRequestControllers=true"
  })]
}

resource "helm_release" "cert_manager_csi_driver" {
  name       = "cert-manager-csi-driver"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager-csi-driver"
  namespace  = "cert-manager"
  version    = var.cert_manager_csi_driver_chart_version
  wait       = true

  depends_on = [helm_release.cert_manager]
}

# --- Pebble (local ACME server) + Let's Encrypt ClusterIssuer ---

resource "kubernetes_namespace_v1" "pebble" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  metadata {
    name = "pebble"
  }
}

resource "kubernetes_config_map_v1" "pebble" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  metadata {
    name      = "pebble-config"
    namespace = kubernetes_namespace_v1.pebble[0].metadata[0].name
  }

  data = {
    "pebble-config.json" = jsonencode({
      pebble = {
        listenAddress                      = "0.0.0.0:14000"
        managementListenAddress            = "0.0.0.0:15000"
        certificate                        = "test/certs/localhost/cert.pem"
        privateKey                         = "test/certs/localhost/key.pem"
        httpPort                           = 5002
        tlsPort                            = 5001
        ocspResponderURL                   = ""
        externalAccountBindingRequired     = false
      }
    })
  }
}

resource "kubernetes_deployment_v1" "pebble" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  metadata {
    name      = "pebble"
    namespace = kubernetes_namespace_v1.pebble[0].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "pebble"
      }
    }

    template {
      metadata {
        labels = {
          app = "pebble"
        }
      }

      spec {
        container {
          name  = "pebble"
          image = "ghcr.io/letsencrypt/pebble:latest"

          args = ["-config", "/etc/pebble/pebble-config.json", "-dnsserver", "8.8.8.8:53"]

          env {
            name  = "PEBBLE_VA_NOSLEEP"
            value = "1"
          }

          env {
            name  = "PEBBLE_VA_ALWAYS_VALID"
            value = "1"
          }

          port {
            container_port = 14000
            name           = "acme"
          }

          port {
            container_port = 15000
            name           = "management"
          }

          volume_mount {
            name       = "pebble-config"
            mount_path = "/etc/pebble"
          }
        }

        volume {
          name = "pebble-config"
          config_map {
            name = kubernetes_config_map_v1.pebble[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "pebble" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  metadata {
    name      = "pebble"
    namespace = kubernetes_namespace_v1.pebble[0].metadata[0].name
  }

  spec {
    selector = {
      app = "pebble"
    }

    port {
      name        = "acme"
      port        = 14000
      target_port = 14000
    }

    port {
      name        = "management"
      port        = 15000
      target_port = 15000
    }
  }
}

resource "kubectl_manifest" "pebble_letsencrypt_issuer" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        server = "https://pebble.pebble.svc.cluster.local:14000/dir"
        privateKeySecretRef = {
          name = "letsencrypt-account-key"
        }
        skipTLSVerify = true
        solvers = [{
          http01 = {
            ingress = {
              ingressClassName = "nginx"
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager, kubernetes_deployment_v1.pebble]
}

resource "kubectl_manifest" "letsencrypt_issuer" {
  count = var.enable_pebble_letsencrypt ? 0 : 1

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-account-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              ingressClassName = "nginx"
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# --- CoreDNS patch for *.ingress.cabotage.dev resolution ---

resource "null_resource" "coredns_ingress_patch" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  triggers = {
    pebble_deployment_uid = kubernetes_deployment_v1.pebble[0].metadata[0].uid
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONTEXT = var.kube_context
    }
    command = <<-EOT
      set -e
      INGRESS_IP=$(kubectl --context $KUBE_CONTEXT get svc -n traefik traefik -o jsonpath='{.spec.clusterIP}')
      kubectl --context $KUBE_CONTEXT get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' \
        | awk -v ip="$INGRESS_IP" -v ans='{{ .Name }}' '
          /template IN A.*ingress\.cabotage\.dev/ { skip=1; next }
          skip && /\}/ { skip=0; next }
          skip { next }
          /kubernetes cluster\.local/ && done==0 {
            print "    template IN A ingress.cabotage.dev {"
            print "        match .*\\.ingress\\.cabotage\\.dev"
            printf "        answer \"%s 60 IN A %s\"\n", ans, ip
            print "        fallthrough"
            print "    }"
            print "    template IN AAAA ingress.cabotage.dev {"
            print "        match .*\\.ingress\\.cabotage\\.dev"
            print "        rcode NOERROR"
            print "        fallthrough"
            print "    }"
            done=1
          }
          { print }
        ' > /tmp/Corefile.patched
      kubectl --context $KUBE_CONTEXT create configmap coredns -n kube-system \
        --from-file=Corefile=/tmp/Corefile.patched --dry-run=client -o yaml \
        | kubectl --context $KUBE_CONTEXT apply -f -
      rm -f /tmp/Corefile.patched
      kubectl --context $KUBE_CONTEXT rollout restart -n kube-system deployment/coredns
    EOT
  }

  depends_on = [kubernetes_deployment_v1.pebble, helm_release.traefik]
}
