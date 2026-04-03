variable "cluster_identifier" {
  description = "Identifier used in CA common names (e.g. cluster ARN)"
  type        = string
}

variable "forwarded_headers_cidrs" {
  description = "CIDR blocks trusted for forwarded headers"
  type        = list(string)
}

variable "proxy_protocol_cidrs" {
  description = "CIDR blocks trusted for proxy protocol"
  type        = list(string)
}

# --- Traefik ---

variable "traefik_chart_version" {
  description = "Helm chart version for Traefik"
  type        = string
  default     = "39.0.5"
}

variable "traefik_replicas" {
  description = "Number of Traefik replicas"
  type        = number
  default     = 2
}

variable "traefik_aws_lb" {
  description = "Enable AWS NLB annotations and LoadBalancer service type for Traefik"
  type        = bool
  default     = true
}

variable "traefik_load_balancer" {
  description = "Use LoadBalancer service type for Traefik (without AWS annotations)"
  type        = bool
  default     = false
}

variable "traefik_host_network" {
  description = "Run Traefik with hostNetwork to bind ports directly on the node (minikube only, NOT for production)"
  type        = bool
  default     = false
}

variable "node_cidr" {
  description = "CIDR for cluster nodes — used in network policies to allow hostNetwork traffic (e.g. traefik with hostNetwork)"
  type        = string
  default     = ""
}

variable "cluster_internal_cidrs" {
  description = "CIDRs to block in tenant egress (pod, service, and node ranges). Tenants can reach the internet but not these ranges. Defaults to RFC1918 + CGNAT + link-local."
  type        = list(string)
  default = [
    "10.0.0.0/8",
    "100.64.0.0/10",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]
}

# --- cert-manager ---

variable "cert_manager_chart_version" {
  description = "Helm chart version for cert-manager"
  type        = string
  default     = "v1.12.15"
}

variable "cert_manager_csi_driver_chart_version" {
  description = "Helm chart version for cert-manager CSI driver"
  type        = string
  default     = "v0.10.2"
}

variable "enable_pebble_letsencrypt" {
  description = "Deploy Pebble local ACME server and Let's Encrypt ClusterIssuer"
  type        = bool
  default     = false
}

variable "acme_email" {
  description = "Email address for ACME (Let's Encrypt) registration"
  type        = string
  default     = "certs@cabotage.io"
}

# --- CA Admission ---

variable "ca_admission_image" {
  description = "Container image for the CA admission webhook"
  type        = string
  default     = "cabotage/cabotage-ca-admission:4.1"
}

variable "ca_admission_replicas" {
  description = "Number of CA admission webhook replicas"
  type        = number
  default     = 2
}

# --- Cabotage App ---

variable "cabotage_app_image" {
  description = "Container image for the cabotage application"
  type        = string
  default     = "ghcr.io/cabotage/cabotage-app:latest"
}

variable "enable_karpenter" {
  description = "Whether Karpenter is enabled — configures node pool tolerations for tenant workloads"
  type        = bool
  default     = false
}

variable "karpenter_standard_pool_name" {
  description = "Name of the Karpenter node pool for non-ephemeral workloads"
  type        = string
  default     = "standard"
}

variable "karpenter_preview_pool_name" {
  description = "Name of the Karpenter node pool for ephemeral workloads"
  type        = string
  default     = "preview"
}

variable "cabotage_app_hostname" {
  description = "Public hostname for the cabotage web app ingress"
  type        = string
}

variable "sentry_environment" {
  description = "Sentry environment name (e.g. staging, production)"
  type        = string
  default     = ""
}

variable "cabotage_app_web_replicas" {
  description = "Number of replicas for the cabotage web deployment"
  type        = number
  default     = 1
}

variable "cabotage_app_worker_replicas" {
  description = "Number of replicas for the cabotage worker deployment"
  type        = number
  default     = 1
}

variable "github_app_id" {
  description = "GitHub App ID for cabotage"
  type        = string
  default     = ""
}

variable "github_oauth_only" {
  description = "Restrict login to GitHub OAuth only"
  type        = bool
  default     = false
}

variable "github_oauth_allowed_orgs" {
  description = "Comma-separated list of GitHub orgs allowed to login via OAuth"
  type        = string
  default     = ""
}

variable "cabotage_ingress_domain" {
  description = "Domain used for ingress of cabotage-managed applications"
  type        = string
  default     = "cabotage.app"
}

# --- Consul ---

variable "consul_image" {
  description = "Container image for Consul"
  type        = string
  default     = "hashicorp/consul:1.20.2"
}

variable "consul_replicas" {
  description = "Number of Consul server replicas"
  type        = number
  default     = 3
}

variable "consul_datacenter" {
  description = "Consul datacenter name"
  type        = string
  default     = "us-east-2"
}

variable "consul_storage_size" {
  description = "Storage size for each Consul server"
  type        = string
  default     = "50Gi"
}

# --- Vault ---

variable "vault_image" {
  description = "Container image for Vault"
  type        = string
  default     = "hashicorp/vault:1.18.4"
}

variable "vault_replicas" {
  description = "Number of Vault server replicas"
  type        = number
  default     = 3
}

variable "vault_auto_unseal_kms_key_id" {
  description = "AWS KMS key ID for Vault auto-unseal (empty to disable)"
  type        = string
  default     = ""
}

variable "vault_auto_unseal_role_arn" {
  description = "IRSA role ARN for Vault KMS auto-unseal (empty to disable)"
  type        = string
  default     = ""
}

variable "vault_auto_unseal_region" {
  description = "AWS region for the KMS key"
  type        = string
  default     = "us-east-1"
}

variable "vault_dev_auto_unseal" {
  description = "Store unseal key in a K8s secret and run a sidecar that auto-unseals (dev only, NOT for production)"
  type        = bool
  default     = false
}

# --- RustFS ---

variable "rustfs_image" {
  description = "Container image for RustFS"
  type        = string
  default     = "rustfs/rustfs:1.0.0-alpha.86"
}

variable "rustfs_replicas" {
  description = "Number of RustFS replicas"
  type        = number
  default     = 4
}

variable "rustfs_disks_per_replica" {
  description = "Number of data disks per RustFS replica (1 for FS mode, 4+ for erasure coding)"
  type        = number
  default     = 4
}

variable "rustfs_storage_size" {
  description = "Storage size for each RustFS data volume"
  type        = string
  default     = "1Gi"
}

variable "rustfs_log_size" {
  description = "Storage size for RustFS log volume"
  type        = string
  default     = "256Mi"
}

# --- CNPG ---

variable "cnpg_chart_version" {
  description = "Helm chart version for CloudNativePG operator"
  type        = string
  default     = "0.27.1"
}

# --- Redis ---

variable "redis_operator_chart_version" {
  description = "Helm chart version for Redis operator"
  type        = string
  default     = "0.19.0"
}

variable "security_confirmable" {
  description = "Enable Flask-Security email confirmation (disable in minikube)"
  type        = bool
  default     = true
}

# --- MFA ---

variable "require_mfa" {
  description = "Require all users to configure MFA (set False for opt-in rollout)"
  type        = bool
  default     = true
}

variable "security_two_factor_always_validate" {
  description = "Require 2FA on every login (disables trust cookies)"
  type        = bool
  default     = false
}

variable "security_two_factor_login_validity" {
  description = "Trust cookie duration (e.g. '30 days')"
  type        = string
  default     = "30 days"
}

variable "security_multi_factor_recovery_codes_n" {
  description = "Number of recovery codes to generate per user"
  type        = number
  default     = 10
}

variable "security_totp_issuer" {
  description = "Issuer name shown in authenticator apps"
  type        = string
  default     = "cabotage"
}

variable "proxy_fix_num_proxies" {
  description = "Number of reverse proxies in front of the app (for ProxyFix / IP tracking)"
  type        = number
  default     = 1
}

variable "registry_verify" {
  description = "TLS verification for registry: 'True' for system trust store, or a path to a CA cert file"
  type        = string
  default     = "True"
}

variable "registry_replicas" {
  description = "Number of registry replicas"
  type        = number
  default     = 1
}

# --- Object Storage ---

variable "s3_storage" {
  description = "S3 storage configuration (from cabotage-eks). When set, S3 is used instead of RustFS."
  type = object({
    region            = string
    registry_bucket   = string
    registry_role_arn = string
    loki_bucket       = string
    loki_role_arn     = string
    mimir_bucket      = string
    mimir_role_arn    = string
  })
  default = null
}

# --- Resident Monitoring ---

variable "loki_backend_replicas" {
  description = "Number of replicas for resident-loki-backend"
  type        = number
  default     = 1
}

variable "loki_read_replicas" {
  description = "Number of replicas for resident-loki-read"
  type        = number
  default     = 1
}

variable "loki_write_replicas" {
  description = "Number of replicas for resident-loki-write"
  type        = number
  default     = 1
}

variable "mimir_backend_replicas" {
  description = "Number of replicas for resident-mimir-backend"
  type        = number
  default     = 1
}

variable "mimir_read_replicas" {
  description = "Number of replicas for resident-mimir-read"
  type        = number
  default     = 1
}

variable "mimir_write_replicas" {
  description = "Number of replicas for resident-mimir-write"
  type        = number
  default     = 1
}

variable "loki_standalone" {
  description = "Run Loki as a single all-in-one process instead of read/write/backend split"
  type        = bool
  default     = false
}

variable "mimir_standalone" {
  description = "Run Mimir as a single all-in-one process instead of read/write/backend split"
  type        = bool
  default     = false
}

# --- Tailscale ---

variable "enable_tailscale" {
  description = "Deploy the tailscale operator (Helm) and operator-manager"
  type        = bool
  default     = false
}

variable "tailscale_operator_chart_version" {
  description = "Helm chart version for the Tailscale operator"
  type        = string
  default     = "1.94.2"
}

variable "tailscale_operator_image" {
  description = "Container image for the Tailscale operator"
  type        = string
  default     = "ewdurbin/ts-k8s-operator"
}

variable "tailscale_operator_image_tag" {
  description = "Image tag for the Tailscale operator"
  type        = string
  default     = "1.97.71-dirty0"
}

variable "tailscale_proxy_image" {
  description = "Container image for Tailscale proxy pods (ProxyGroup)"
  type        = string
  default     = "ewdurbin/ts-tailscale"
}

variable "tailscale_proxy_image_tag" {
  description = "Image tag for Tailscale proxy pods"
  type        = string
  default     = "1.97.71-dirty0"
}

variable "tailscale_tag_prefix" {
  description = "Prefix for Tailscale ACL tags (e.g. cabotage → tag:cabotage-operator, tag:cabotage)"
  type        = string
  default     = "cabotage"
}

variable "enable_tailscale_ingress" {
  description = "Deploy the Tailscale Funnel ingress for the cabotage app (requires enable_tailscale)"
  type        = bool
  default     = false
}

variable "cabotage_tailscale_hostname" {
  description = "Tailscale machine name for the cabotage app Funnel ingress"
  type        = string
  default     = "cabotage-minikube"
}

variable "tailscale_operator_hostname" {
  description = "Tailscale machine name for the operator itself"
  type        = string
  default     = "tailscale-operator"
}

variable "tailscale_operator_irsa_role_arn" {
  description = "IRSA role ARN for the Tailscale operator (required when enable_tailscale is true)"
  type        = string
  default     = ""
}

variable "tailscale_workload_identity_client_id" {
  description = "Tailscale OIDC client ID for workload identity federation"
  type        = string
  default     = ""
}

variable "tailscale_workload_identity_audience" {
  description = "Tailscale OIDC audience for workload identity federation"
  type        = string
  default     = ""
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale static OAuth client ID (used when WIF is not available, e.g. minikube)"
  type        = string
  default     = ""
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale static OAuth client secret (used when WIF is not available, e.g. minikube)"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Terraform ---

variable "secrets_dir" {
  description = "Local directory to store bootstrap secrets (consul mgmt token, vault root token, unseal key). Used when secrets_manager_prefix is empty."
  type        = string
  default     = ".secrets"
}

variable "secrets_manager_prefix" {
  description = "AWS Secrets Manager prefix (e.g. 'cabotage/prod-cluster'). When non-empty, secrets are stored in SM instead of secrets_dir."
  type        = string
  default     = ""
}

variable "secrets_manager_region" {
  description = "AWS region for Secrets Manager API calls. Required when secrets_manager_prefix is set."
  type        = string
  default     = ""
}

variable "secrets_manager_profile" {
  description = "AWS CLI profile for Secrets Manager API calls. Should match the profile used by the AWS Terraform provider."
  type        = string
  default     = ""
}

variable "ca_cert_file" {
  description = "Path to root CA certificate (public, safe to commit)"
  type        = string
  default     = "ca.crt"
}

variable "kube_context" {
  description = "Kubernetes context name for kubectl commands in local-exec provisioners"
  type        = string
}

variable "consul_local_port" {
  description = "Local port for consul port-forward (use different ports for concurrent applies)"
  type        = number
  default     = 18500
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
