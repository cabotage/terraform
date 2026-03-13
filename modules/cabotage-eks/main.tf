locals {
  tags = merge(
    {
      Project     = var.project_name
      ClusterName = var.cluster_name
    },
    var.tags,
  )

}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = var.cluster_endpoint_public_access
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = tostring(var.enable_network_policy)
        env = {
          ENABLE_PREFIX_DELEGATION = tostring(var.enable_prefix_delegation)
        }
      })
    }
  }

  eks_managed_node_groups = {
    for name, config in var.node_groups : name => merge(config, {
      cloudinit_pre_nodeadm = length(var.ingress_hairpin_domains) > 0 ? [
        {
          content_type = "text/x-shellscript"
          content      = <<-EOT
            #!/bin/bash
            # Add NodeLocal DNS as primary resolver for ingress hairpin routing
            sed -i '1s/^/nameserver 169.254.20.10\n/' /etc/resolv.conf
          EOT
        }
      ] : []
    })
  }

  tags = local.tags
}

# --- Vault KMS Auto-Unseal ---

resource "aws_kms_key" "vault_unseal" {
  count = var.enable_vault_auto_unseal ? 1 : 0

  description = "Vault auto-unseal key for ${var.cluster_name}"
  key_usage   = "ENCRYPT_DECRYPT"

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-vault-unseal"
  })
}

resource "aws_kms_alias" "vault_unseal" {
  count = var.enable_vault_auto_unseal ? 1 : 0

  name          = "alias/${var.cluster_name}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal[0].key_id
}

module "vault_unseal_irsa" {
  count   = var.enable_vault_auto_unseal ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-vault-unseal"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.vault_namespace}:vault"]
    }
  }

  tags = local.tags
}

resource "aws_iam_role_policy" "vault_unseal_kms" {
  count = var.enable_vault_auto_unseal ? 1 : 0

  name = "vault-kms-unseal"
  role = module.vault_unseal_irsa[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
        Resource = [aws_kms_key.vault_unseal[0].arn]
      }
    ]
  })
}

# --- EBS CSI Driver ---

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.arn

  tags = local.tags

  depends_on = [module.eks]
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = var.gp3_as_default_storage_class ? "true" : "false"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# --- AWS Load Balancer Controller ---

module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_lb_controller_chart_version

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    vpcId       = module.vpc.vpc_id
    serviceAccount = {
      name = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.aws_lb_controller_irsa.arn
      }
    }
  })]

  depends_on = [module.eks]
}

# --- Metrics Server ---

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_chart_version

  depends_on = [module.eks]
}

# --- NodeLocal DNSCache ---

resource "helm_release" "node_local_dns" {
  name       = "node-local-dns"
  repository = "oci://ghcr.io/deliveryhero/helm-charts"
  chart      = "node-local-dns"
  namespace  = "kube-system"
  version    = var.node_local_dns_chart_version

  values = [yamlencode({
    config = {
      localDns = "169.254.20.10"
      bindIp   = true
      extraServerBlocks = length(var.ingress_hairpin_domains) > 0 ? join("\n", [for domain in var.ingress_hairpin_domains : <<-EOF
        ${domain}:53 {
            errors
            cache 300
            bind 169.254.20.10 172.20.0.10
            template IN A ${domain} {
                match .*\.${replace(domain, ".", "\\.")}
                answer "{{.Name}} 60 IN A ${kubernetes_service_v1.ingress_hairpin[0].spec[0].cluster_ip}"
                fallthrough
            }
            template IN A ${domain} {
                match ^${replace(domain, ".", "\\.")}[.]$
                answer "{{.Name}} 60 IN A ${kubernetes_service_v1.ingress_hairpin[0].spec[0].cluster_ip}"
                fallthrough
            }
            template IN AAAA ${domain} {
                match .*
                rcode NOERROR
            }
        }
      EOF
      ]) : ""
    }
  })]

  depends_on = [module.eks]
}

# --- Ingress Hairpin Routing ---

resource "kubernetes_namespace_v1" "ingress_controller" {
  count = length(var.ingress_hairpin_domains) > 0 ? 1 : 0

  metadata {
    name = var.ingress_controller_namespace
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_v1" "ingress_hairpin" {
  count = length(var.ingress_hairpin_domains) > 0 ? 1 : 0

  metadata {
    name      = "ingress-hairpin"
    namespace = var.ingress_controller_namespace
  }

  spec {
    type = "ClusterIP"

    selector = var.ingress_controller_selector

    port {
      name        = "https"
      port        = 443
      target_port = "websecure"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "web"
    }
  }

  depends_on = [kubernetes_namespace_v1.ingress_controller]
}

