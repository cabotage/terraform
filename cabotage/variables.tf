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
  default     = "cabotage/cabotage-ca-admission:4"
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

variable "secrets_dir" {
  description = "Local directory to store bootstrap secrets (consul mgmt token, vault root token, unseal key)"
  type        = string
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
