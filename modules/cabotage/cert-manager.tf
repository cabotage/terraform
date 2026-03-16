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

# --- Let's Encrypt ClusterIssuer (CA-based for dev, ACME for prod) ---

resource "kubectl_manifest" "ca_letsencrypt_issuer" {
  count = var.enable_pebble_letsencrypt ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      ca = {
        secretName = "operators-ca-key-pair"
      }
    }
  })

  depends_on = [null_resource.sign_intermediate_cas]
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
    cluster_id = var.cluster_identifier
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

  depends_on = [helm_release.traefik]
}
