# --- Karpenter ---

module "karpenter" {
  count   = var.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true
  namespace                       = "kube-system"

  create_node_iam_role = true
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = "kube-system"
  version    = var.karpenter_chart_version

  values = [yamlencode({
    settings = {
      clusterName       = module.eks.cluster_name
      clusterEndpoint   = module.eks.cluster_endpoint
      interruptionQueue = module.karpenter[0].queue_name
    }
  })]

  depends_on = [module.eks]
}

# --- EC2NodeClass (shared by both pools) ---

resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiSelectorTerms = [{
        alias = "al2023@${var.karpenter_ami_alias_version}"
      }]
      role = module.karpenter[0].node_iam_role_name
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.cluster_name
        }
      }]
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.cluster_name
        }
      }]
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeType          = "gp3"
          volumeSize          = var.karpenter_ebs_volume_size
          throughput          = var.karpenter_ebs_throughput
          deleteOnTermination = true
        }
      }]
      userData = yamlencode({
        apiVersion = "node.eks.aws/v1alpha1"
        kind       = "NodeConfig"
        spec = {
          kubelet = {
            config = {
              serializeImagePulls = false
            }
          }
        }
      })
      tags = merge(local.tags, {
        "karpenter.sh/discovery" = var.cluster_name
      })
    }
  })

  depends_on = [helm_release.karpenter]
}

# --- NodePool: standard ---

resource "kubectl_manifest" "karpenter_node_pool_standard" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "standard"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "cabotage.dev/node-pool" = "standard"
          }
        }
        spec = {
          taints = [{
            key    = "cabotage.dev/node-pool"
            value  = "standard"
            effect = "NoSchedule"
          }]
          requirements = [
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.karpenter_standard_instance_families
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = var.karpenter_standard_instance_sizes
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
        }
      }
      limits = {
        cpu = var.karpenter_standard_cpu_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

# --- NodePool: preview ---

resource "kubectl_manifest" "karpenter_node_pool_preview" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "preview"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "cabotage.dev/node-pool" = "preview"
          }
        }
        spec = {
          taints = [{
            key    = "cabotage.dev/node-pool"
            value  = "preview"
            effect = "NoSchedule"
          }]
          requirements = [
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.karpenter_preview_instance_families
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = var.karpenter_preview_instance_sizes
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
        }
      }
      limits = {
        cpu = var.karpenter_preview_cpu_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

# --- Pre-warm (overprovisioning) ---

locals {
  prewarm_enabled = var.enable_karpenter && (var.karpenter_standard_prewarm_enabled || var.karpenter_preview_prewarm_enabled)
}

resource "kubectl_manifest" "prewarm_namespace" {
  count = local.prewarm_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name   = "overprovisioning"
      labels = local.tags
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "prewarm_priority_class" {
  count = local.prewarm_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "scheduling.k8s.io/v1"
    kind       = "PriorityClass"
    metadata = {
      name = "placeholder"
    }
    value         = -1000
    globalDefault = false
    description   = "Negative priority for placeholder pods to enable overprovisioning."
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "prewarm_standard" {
  count = var.enable_karpenter && var.karpenter_standard_prewarm_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "capacity-reservation-standard"
      namespace = "overprovisioning"
    }
    spec = {
      replicas = var.karpenter_standard_prewarm_replicas
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "capacity-placeholder"
          "app.kubernetes.io/instance" = "standard"
        }
      }
      template = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"     = "capacity-placeholder"
            "app.kubernetes.io/instance" = "standard"
          }
          annotations = {
            "kubernetes.io/description" = "Capacity reservation for standard node pool"
          }
        }
        spec = {
          priorityClassName = "placeholder"
          nodeSelector = {
            "cabotage.dev/node-pool" = "standard"
          }
          tolerations = [{
            key      = "cabotage.dev/node-pool"
            value    = "standard"
            operator = "Equal"
            effect   = "NoSchedule"
          }]
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/name"     = "capacity-placeholder"
                      "app.kubernetes.io/instance" = "standard"
                    }
                  }
                  topologyKey = "topology.kubernetes.io/hostname"
                }
              }]
            }
          }
          containers = [{
            name  = "pause"
            image = "registry.k8s.io/pause:3.6"
            resources = {
              requests = {
                cpu    = var.karpenter_standard_prewarm_cpu_requests
                memory = var.karpenter_standard_prewarm_memory_requests
              }
              limits = {
                cpu    = var.karpenter_standard_prewarm_cpu_limits
                memory = var.karpenter_standard_prewarm_memory_limits
              }
            }
          }]
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.prewarm_namespace,
    kubectl_manifest.prewarm_priority_class,
    kubectl_manifest.karpenter_node_pool_standard,
  ]
}

resource "kubectl_manifest" "prewarm_preview" {
  count = var.enable_karpenter && var.karpenter_preview_prewarm_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "capacity-reservation-preview"
      namespace = "overprovisioning"
    }
    spec = {
      replicas = var.karpenter_preview_prewarm_replicas
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "capacity-placeholder"
          "app.kubernetes.io/instance" = "preview"
        }
      }
      template = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"     = "capacity-placeholder"
            "app.kubernetes.io/instance" = "preview"
          }
          annotations = {
            "kubernetes.io/description" = "Capacity reservation for preview node pool"
          }
        }
        spec = {
          priorityClassName = "placeholder"
          nodeSelector = {
            "cabotage.dev/node-pool" = "preview"
          }
          tolerations = [{
            key      = "cabotage.dev/node-pool"
            value    = "preview"
            operator = "Equal"
            effect   = "NoSchedule"
          }]
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/name"     = "capacity-placeholder"
                      "app.kubernetes.io/instance" = "preview"
                    }
                  }
                  topologyKey = "topology.kubernetes.io/hostname"
                }
              }]
            }
          }
          containers = [{
            name  = "pause"
            image = "registry.k8s.io/pause:3.6"
            resources = {
              requests = {
                cpu    = var.karpenter_preview_prewarm_cpu_requests
                memory = var.karpenter_preview_prewarm_memory_requests
              }
              limits = {
                cpu    = var.karpenter_preview_prewarm_cpu_limits
                memory = var.karpenter_preview_prewarm_memory_limits
              }
            }
          }]
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.prewarm_namespace,
    kubectl_manifest.prewarm_priority_class,
    kubectl_manifest.karpenter_node_pool_preview,
  ]
}
