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
    region            = data.aws_region.current.id
    registry_bucket   = aws_s3_bucket.storage["registry"].bucket
    registry_role_arn = module.s3_irsa["registry"].arn
    loki_bucket       = aws_s3_bucket.storage["loki"].bucket
    loki_role_arn     = module.s3_irsa["loki"].arn
    mimir_bucket      = aws_s3_bucket.storage["mimir"].bucket
    mimir_role_arn    = module.s3_irsa["mimir"].arn
  } : null
}

output "fargate_pod_execution_role_arn" {
  description = "ARN of the Fargate pod execution role (empty if disabled)"
  value       = var.enable_fargate ? aws_iam_role.fargate_pod_execution[0].arn : ""
}

output "fargate_manager_irsa_role_arn" {
  description = "IRSA role ARN for cabotage to manage Fargate profiles (empty if disabled)"
  value       = var.enable_fargate ? module.fargate_manager_irsa[0].arn : ""
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
