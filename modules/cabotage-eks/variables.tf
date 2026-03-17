variable "project_name" {
  description = "Project name, applied as a tag to all AWS resources"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ, /19 recommended for pod IP space)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (set false for HA in production)"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS API server endpoint"
  type        = bool
  default     = true
}

variable "enable_prefix_delegation" {
  description = "Enable VPC CNI prefix delegation for higher pod density per node"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable native VPC CNI network policy enforcement"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Map of EKS managed node group definitions"
  type        = any
  default = {
    default = {
      instance_types = ["m8g.xlarge"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
    }
  }
}

variable "node_group_disk_size" {
  description = "Root EBS volume size in GiB for EKS managed node groups"
  type        = number
  default     = 20
}

variable "gp3_as_default_storage_class" {
  description = "Set the gp3 StorageClass as the cluster default"
  type        = bool
  default     = true
}

variable "aws_lb_controller_chart_version" {
  description = "Helm chart version for the AWS Load Balancer Controller"
  type        = string
  default     = "3.1.0"
}

variable "metrics_server_chart_version" {
  description = "Helm chart version for the Metrics Server"
  type        = string
  default     = "3.13.0"
}

variable "node_local_dns_chart_version" {
  description = "Helm chart version for NodeLocal DNSCache"
  type        = string
  default     = "2.7.0"
}

variable "ingress_hairpin_domains" {
  description = "Domains to hairpin via the in-cluster ingress controller. All *.domain queries from nodes will resolve to the ingress controller's internal ClusterIP."
  type        = list(string)
  default     = []
}

variable "ingress_controller_namespace" {
  description = "Namespace where the ingress controller (Traefik) is deployed"
  type        = string
  default     = "traefik"
}

variable "ingress_controller_selector" {
  description = "Label selector for the ingress controller pods"
  type        = map(string)
  default = {
    "app.kubernetes.io/name" = "traefik"
  }
}

variable "enable_vault_auto_unseal" {
  description = "Create a KMS key and IRSA role for Vault auto-unseal"
  type        = bool
  default     = false
}

variable "vault_namespace" {
  description = "Kubernetes namespace where Vault runs (for IRSA binding)"
  type        = string
  default     = "cabotage"
}

# --- S3 Storage ---

variable "enable_s3_storage" {
  description = "Create S3 buckets and IAM users for registry, loki, and mimir (alternative to RustFS)"
  type        = bool
  default     = false
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names (e.g. 'myproject' creates myproject-registry, myproject-loki, myproject-mimir)"
  type        = string
  default     = ""
}

variable "cluster_enabled_log_types" {
  description = "List of EKS control plane log types to enable. Valid values: api, audit, authenticator, controllerManager, scheduler."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Number of days to retain EKS control plane log events."
  type        = number
  default     = 90
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant the current caller admin access to the EKS cluster. Disable this to manage access entries explicitly via the access_entries variable."
  type        = bool
  default     = true
}

variable "access_entries" {
  description = "Map of access entries to add to the EKS cluster."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
