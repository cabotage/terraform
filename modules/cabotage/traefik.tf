# --- Traefik Ingress Controller / Gateway API ---
# Step 1 in start-cluster

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name
  version    = var.traefik_chart_version

  values = [yamlencode({
    deployment = {
      replicas = var.traefik_replicas
    }

    logs = {
      access = {
        enabled = true
        format  = "json"
      }
    }

    ports = {
      web = {
        forwardedHeaders = {
          trustedIPs = var.forwarded_headers_cidrs
        }
        proxyProtocol = {
          trustedIPs = var.proxy_protocol_cidrs
        }
      }
      websecure = {
        forwardedHeaders = {
          trustedIPs = var.forwarded_headers_cidrs
        }
        proxyProtocol = {
          trustedIPs = var.proxy_protocol_cidrs
        }
      }
    }

    providers = {
      kubernetesIngressNginx = {
        enabled = true
      }
    }

    metrics = {
      datadog = {
        address               = "$(DD_AGENT_HOST):8125"
        addEntryPointsLabels  = true
        addRoutersLabels      = true
        addServicesLabels     = true
      }
      prometheus = {
        addServicesLabels    = true
        addRoutersLabels     = true
        addEntryPointsLabels = true
        buckets              = "0.005,0.01,0.025,0.05,0.1,0.25,0.5,1.0,2.5,5.0,10.0,30.0,60.0,120.0"
      }
    }

    env = [
      {
        name = "DD_AGENT_HOST"
        valueFrom = {
          fieldRef = {
            fieldPath = "status.hostIP"
          }
        }
      }
    ]

    volumes = [{
      name      = "cabotage-ca"
      mountPath = "/etc/traefik/certs"
      type      = "configMap"
    }]

    additionalArguments = [
      "--serversTransport.rootCAs=/etc/traefik/certs/ca.crt"
    ]

    service = var.traefik_aws_lb ? {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol"              = "*"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                      = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-type"                        = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"             = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout"     = "240"
        "service.beta.kubernetes.io/aws-load-balancer-connection-draining-enabled" = "true"
        "service.beta.kubernetes.io/aws-load-balancer-connection-draining-timeout" = "240"
      }
    } : {
      type        = "NodePort"
      annotations = {}
    }
  })]

  depends_on = [kubernetes_config_map_v1.traefik_cabotage_ca]
}

# --- Cabotage CA in Traefik namespace ---

resource "kubernetes_config_map_v1" "traefik_cabotage_ca" {
  metadata {
    name      = "cabotage-ca"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  data = {
    "ca.crt" = data.local_file.root_ca_cert.content
  }
}

resource "kubectl_manifest" "nginx_ingress_class" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = "nginx"
    }
    spec = {
      controller = "k8s.io/ingress-nginx"
    }
  })

  depends_on = [helm_release.traefik]
}
