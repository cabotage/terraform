output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA/Pod Identity"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "vault_unseal_kms_key_id" {
  description = "KMS key ID for Vault auto-unseal (empty if disabled)"
  value       = var.enable_vault_auto_unseal ? aws_kms_key.vault_unseal[0].key_id : ""
}

output "vault_unseal_irsa_role_arn" {
  description = "IRSA role ARN for Vault auto-unseal (empty if disabled)"
  value       = var.enable_vault_auto_unseal ? module.vault_unseal_irsa[0].arn : ""
}

output "s3_storage" {
  description = "S3 storage configuration for the cabotage module (null when disabled)"
  value = var.enable_s3_storage ? {
    region                          = data.aws_region.current.id
    registry_bucket                 = aws_s3_bucket.storage["registry"].bucket
    registry_role_arn               = module.s3_irsa["registry"].arn
    loki_bucket                     = aws_s3_bucket.storage["loki"].bucket
    loki_role_arn                   = module.s3_irsa["loki"].arn
    mimir_bucket                    = aws_s3_bucket.storage["mimir"].bucket
    mimir_role_arn                  = module.s3_irsa["mimir"].arn
    postgres_backup_bucket          = aws_s3_bucket.storage["postgres_backup"].bucket
    postgres_backup_role_arn        = module.s3_irsa["postgres_backup"].arn
    tenant_postgres_backup_role_arn = aws_iam_role.tenant_postgres_backup_irsa[0].arn
  } : null
}

output "node_group_autoscaling_group_names" {
  description = "Map of node group names to their autoscaling group names"
  value       = { for name, group in module.eks.eks_managed_node_groups : name => group.node_group_autoscaling_group_names }
}

output "tailscale_operator_irsa_role_arn" {
  description = "IRSA role ARN for the Tailscale operator (empty if disabled)"
  value       = var.enable_cabotage_tailscale_ingress ? module.tailscale_operator_irsa[0].arn : ""
}

output "tailscale_subnet_router_autoscaling_group_name" {
  description = "Name of the Tailscale subnet router autoscaling group (empty if disabled)"
  value       = var.enable_tailscale_subnet_router ? aws_autoscaling_group.tailscale_subnet_router[0].name : ""
}

output "tailscale_subnet_router_role_arn" {
  description = "IAM role ARN for the Tailscale subnet router (use as Subject in Tailscale trust credential)"
  value       = var.enable_tailscale_subnet_router ? aws_iam_role.tailscale_subnet_router[0].arn : ""
}

output "tailscale_setup" {
  description = "Tailscale configuration guide: trust credential settings and ACL snippet (null when disabled)"
  value = var.enable_tailscale_subnet_router ? {
    trust_credential = {
      type    = "OpenID Connect"
      issuer  = "AWS"
      subject = aws_iam_role.tailscale_subnet_router[0].arn
      scopes  = ["Devices > Core: Write", "Devices > Routes: Write", "Keys > Auth Keys: Write"]
    }
    acl_snippet = <<-EOT
      "autoApprovers": {
        "routes": {
          "${var.vpc_cidr}": ${jsonencode(var.tailscale_subnet_router_tags)}
        }
      },
      "acls": [
        {"action": "accept", "src": ["group:devs"], "dst": ["${var.vpc_cidr}:443"]},
        {"action": "accept", "src": ["tag:ci"],      "dst": ["${var.vpc_cidr}:443"]}
      ]
    EOT
    split_dns = {
      domain     = "*.eks.amazonaws.com"
      nameserver = cidrhost(var.vpc_cidr, 2)
    }
  } : null
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN for Karpenter-launched nodes (empty if disabled)"
  value       = var.enable_karpenter ? module.karpenter[0].node_iam_role_arn : ""
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling (empty if disabled)"
  value       = var.enable_karpenter ? module.karpenter[0].queue_name : ""
}

output "karpenter_backing_services_pool_name" {
  description = "Name of the Karpenter node pool for backing services (empty if disabled)"
  value       = var.enable_karpenter ? var.karpenter_backing_services_pool_name : ""
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.vpc_cidr
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}
