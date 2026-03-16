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
  default     = false
}

variable "traefik_load_balancer" {
  description = "Use LoadBalancer service type for Traefik (without AWS annotations)"
  type        = bool
  default     = false
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

variable "cabotage_app_hostname" {
  description = "Public hostname for the cabotage web app ingress"
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID for cabotage"
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
  default     = "rustfs/rustfs:1.0.0-alpha.82"
}

variable "rustfs_replicas" {
  description = "Number of RustFS replicas"
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

variable "registry_replicas" {
  description = "Number of registry replicas"
  type        = number
  default     = 1
}

variable "secrets_dir" {
  description = "Local directory to store bootstrap secrets (consul mgmt token, vault root token, unseal key)"
  type        = string
  default     = ".secrets"
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
