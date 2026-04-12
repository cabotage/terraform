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

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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

variable "node_group_release_version" {
  description = "EKS AMI release version to pin for managed node groups (e.g. '1.35.2-20260216', empty string uses latest)"
  type        = string
  default     = ""
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
  description = "Create S3 buckets and IAM users for registry, loki, and mimir (alternative to SeaweedFS)"
  type        = bool
  default     = false
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names (e.g. 'myproject' creates myproject-registry, myproject-loki, myproject-mimir)"
  type        = string
  default     = ""
}

variable "kms_key_administrators" {
  description = "A list of IAM ARNs for KMS key administrators. If not set, the current caller identity is used."
  type        = list(string)
  default     = []
}

variable "enabled_log_types" {
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

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs. Logs are sent to a CloudWatch log group."
  type        = bool
  default     = false
}

variable "vpc_flow_log_retention_in_days" {
  description = "Number of days to retain VPC flow log events in CloudWatch."
  type        = number
  default     = 365
}

variable "vpc_flow_log_traffic_type" {
  description = "The type of traffic to capture. Valid values: ACCEPT, REJECT, ALL."
  type        = string
  default     = "ALL"
}

variable "enable_tailscale_subnet_router" {
  description = "Deploy an EC2-based Tailscale subnet router that advertises VPC routes to your tailnet"
  type        = bool
  default     = false
}

variable "tailscale_workload_identity_client_id" {
  description = "Tailscale OIDC client ID for workload identity federation (from Tailscale admin Trust Credentials)"
  type        = string
  default     = ""
}

variable "tailscale_workload_identity_audience" {
  description = "Tailscale OIDC audience for workload identity federation"
  type        = string
  default     = ""
}

variable "enable_cabotage_tailscale_ingress" {
  description = "Enable IRSA for the Tailscale operator to authenticate via OIDC (for cabotage tailscale ingress)"
  type        = bool
  default     = false
}

variable "cabotage_tailscale_workload_identity_client_id" {
  description = "Tailscale OIDC client ID for the cabotage operator's workload identity (separate from subnet router)"
  type        = string
  default     = ""
}

variable "cabotage_tailscale_workload_identity_audience" {
  description = "Tailscale OIDC audience for the cabotage operator's workload identity (separate from subnet router)"
  type        = string
  default     = ""
}

variable "tailscale_operator_namespace" {
  description = "Kubernetes namespace where the Tailscale operator runs"
  type        = string
  default     = "tailscale"
}

variable "tailscale_operator_service_account" {
  description = "Kubernetes service account name for the Tailscale operator"
  type        = string
  default     = "operator"
}

variable "tailscale_subnet_router_tags" {
  description = "Tailscale ACL tags to apply to the subnet router node"
  type        = list(string)
  default     = ["tag:subnet-router"]
}

variable "tailscale_subnet_router_ami_id" {
  description = "AMI ID for the Tailscale subnet router instances (empty string uses latest AL2023 ARM)"
  type        = string
  default     = ""
}

variable "tailscale_subnet_router_instance_type" {
  description = "EC2 instance type for the Tailscale subnet router"
  type        = string
  default     = "t4g.nano"
}

variable "tailscale_subnet_router_hostname" {
  description = "Tailscale hostname prefix for the subnet router nodes (instance ID is appended automatically)"
  type        = string
  default     = ""
}

# --- Karpenter ---

variable "enable_karpenter" {
  description = "Deploy Karpenter for node autoscaling (standard and preview pools)"
  type        = bool
  default     = false
}

variable "karpenter_chart_version" {
  description = "Helm chart version for Karpenter"
  type        = string
  default     = "1.10.0"
}

variable "karpenter_ami_alias_version" {
  description = "AL2023 AMI alias version for Karpenter EC2NodeClass (e.g. 'v20240807' to pin, or 'latest' for non-production)"
  type        = string
  default     = "latest"
}

variable "karpenter_ebs_volume_size" {
  description = "Root volume size for Karpenter nodes (e.g. '32Gi')."
  type        = string
  default     = "32Gi"
}

variable "karpenter_ebs_throughput" {
  description = "EBS throughput (MB/s) for Karpenter node root volumes."
  type        = number
  default     = 125
}

variable "karpenter_standard_instance_families" {
  description = "Instance families for the standard Karpenter node pool"
  type        = list(string)
  default     = ["m8g", "c8g", "r8g"]
}

variable "karpenter_standard_instance_sizes" {
  description = "Allowed instance sizes for the standard Karpenter node pool"
  type        = list(string)
  default     = ["large", "xlarge", "2xlarge", "4xlarge"]
}

variable "karpenter_standard_cpu_limit" {
  description = "Maximum total vCPUs the standard node pool can provision"
  type        = number
  default     = 100
}

variable "karpenter_preview_instance_families" {
  description = "Instance families for the preview Karpenter node pool"
  type        = list(string)
  default     = ["m8g", "c8g", "r8g"]
}

variable "karpenter_preview_instance_sizes" {
  description = "Allowed instance sizes for the preview Karpenter node pool"
  type        = list(string)
  default     = ["medium", "large", "xlarge", "2xlarge"]
}

variable "karpenter_preview_cpu_limit" {
  description = "Maximum total vCPUs the preview node pool can provision"
  type        = number
  default     = 50
}

# --- Pre-warm (overprovisioning) ---

variable "karpenter_standard_prewarm_enabled" {
  description = "Enable capacity reservation (pre-warm) for the standard node pool"
  type        = bool
  default     = false
}

variable "karpenter_standard_prewarm_replicas" {
  description = "Number of placeholder pods for the standard node pool"
  type        = number
  default     = 6
}

variable "karpenter_standard_prewarm_cpu_requests" {
  description = "CPU request per placeholder pod for the standard node pool"
  type        = string
  default     = "500m"
}

variable "karpenter_standard_prewarm_cpu_limits" {
  description = "CPU limit per placeholder pod for the standard node pool"
  type        = string
  default     = "1000m"
}

variable "karpenter_standard_prewarm_memory_requests" {
  description = "Memory request per placeholder pod for the standard node pool"
  type        = string
  default     = "1024Mi"
}

variable "karpenter_standard_prewarm_memory_limits" {
  description = "Memory limit per placeholder pod for the standard node pool"
  type        = string
  default     = "1536Mi"
}

variable "karpenter_preview_prewarm_enabled" {
  description = "Enable capacity reservation (pre-warm) for the preview node pool"
  type        = bool
  default     = false
}

variable "karpenter_preview_prewarm_replicas" {
  description = "Number of placeholder pods for the preview node pool"
  type        = number
  default     = 6
}

variable "karpenter_preview_prewarm_cpu_requests" {
  description = "CPU request per placeholder pod for the preview node pool"
  type        = string
  default     = "500m"
}

variable "karpenter_preview_prewarm_cpu_limits" {
  description = "CPU limit per placeholder pod for the preview node pool"
  type        = string
  default     = "1000m"
}

variable "karpenter_preview_prewarm_memory_requests" {
  description = "Memory request per placeholder pod for the preview node pool"
  type        = string
  default     = "1024Mi"
}

variable "karpenter_preview_prewarm_memory_limits" {
  description = "Memory limit per placeholder pod for the preview node pool"
  type        = string
  default     = "1536Mi"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
