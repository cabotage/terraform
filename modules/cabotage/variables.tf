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
  default     = "39.0.7"
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

variable "traefik_nlb_idle_timeout" {
  description = "AWS NLB connection idle timeout in seconds"
  type        = number
  default     = 240
}

variable "traefik_responding_timeouts" {
  description = "Traefik entrypoint responding timeouts"
  type = object({
    read_timeout  = string
    write_timeout = string
  })
  default = {
    read_timeout  = "60s"
    write_timeout = "0s"
  }
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
  default     = "v1.20.1"
}

variable "cert_manager_csi_driver_chart_version" {
  description = "Helm chart version for cert-manager CSI driver"
  type        = string
  default     = "v0.13.0"
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

variable "ca_admission_resources" {
  description = "CPU/memory requests and limits for the CA admission webhook"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "48Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "48Mi"
    }
  }
}

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

variable "cabotage_sidecar_resources" {
  description = "CPU/memory requests and limits for cabotage-sidecar (vault token manager) native sidecars"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "16Mi"
    }
    limits = {
      cpu    = "10m"
      memory = "16Mi"
    }
  }
}

variable "cabotage_sidecar_tls_resources" {
  description = "CPU/memory requests and limits for cabotage-sidecar-tls (ghostunnel) native sidecar"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "32Mi"
    }
    limits = {
      cpu    = "10m"
      memory = "32Mi"
    }
  }
}

variable "cabotage_app_web_resources" {
  description = "CPU/memory requests and limits for the cabotage web Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "768Mi"
    }
    limits = {
      cpu    = "1"
      memory = "1024Mi"
    }
  }
}

variable "cabotage_app_worker_resources" {
  description = "CPU/memory requests and limits for the cabotage worker Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "250m"
      memory = "1Gi"
    }
  }
}

variable "cabotage_app_worker_beat_resources" {
  description = "CPU/memory requests and limits for the cabotage worker-beat Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "256Mi"
    }
  }
}

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

variable "cabotage_postgres_resources" {
  description = "CPU/memory requests and limits for the cabotage CNPG postgres cluster"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "512Mi"
    }
  }
}

variable "cabotage_postgres_parameters" {
  description = "PostgreSQL configuration parameters for the cabotage CNPG cluster (e.g. shared_buffers, work_mem)"
  type        = map(string)
  default     = {
    shared_buffers = "128MB"
  }
}

variable "cabotage_postgres_instances" {
  description = "Number of PostgreSQL instances in the cabotage CNPG cluster"
  type        = number
  default     = 2
}

variable "cabotage_postgres_storage_size" {
  description = "Storage size for the cabotage CNPG postgres cluster"
  type        = string
  default     = "1Gi"
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

variable "consul_resources" {
  description = "CPU/memory requests and limits for the Consul container"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "256Mi"
    }
  }
}

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

variable "vault_consul_agent_resources" {
  description = "CPU/memory requests and limits for the Consul agent sidecar in Vault pods"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "48Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "48Mi"
    }
  }
}

variable "cert_watcher_resources" {
  description = "CPU/memory requests and limits for cert-watcher sidecars (Vault and Consul)"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "5m"
      memory = "8Mi"
    }
    limits = {
      cpu    = "5m"
      memory = "8Mi"
    }
  }
}

variable "vault_auto_unseal_resources" {
  description = "CPU/memory requests and limits for the Vault auto-unseal sidecar (dev only)"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "32Mi"
    }
    limits = {
      cpu    = "10m"
      memory = "32Mi"
    }
  }
}

variable "vault_resources" {
  description = "CPU/memory requests and limits for the Vault container"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "128Mi"
    }
  }
}

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

variable "rustfs_resources" {
  description = "CPU/memory requests and limits for the RustFS container"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

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
  default     = "0.28.0"
}

# --- Redis ---

variable "redis_resources" {
  description = "CPU/memory requests and limits for the Redis container"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "128Mi"
    }
  }
}

variable "redis_exporter_resources" {
  description = "CPU/memory requests and limits for the Redis Exporter sidecar"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "32Mi"
    }
    limits = {
      cpu    = "10m"
      memory = "32Mi"
    }
  }
}

variable "redis_operator_chart_version" {
  description = "Helm chart version for Redis operator"
  type        = string
  default     = "0.23.0"
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

variable "registry_ghostunnel_resources" {
  description = "CPU/memory requests and limits for the registry ghostunnel sidecar"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "32Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "32Mi"
    }
  }
}

variable "registry_resources" {
  description = "CPU/memory requests and limits for the registry container"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "128Mi"
    }
  }
}

variable "enrollment_operator_resources" {
  description = "CPU/memory requests and limits for the Enrollment Operator Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "128Mi"
    }
  }
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

variable "alloy_resources" {
  description = "CPU/memory requests and limits for the Alloy DaemonSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "512Mi"
    }
  }
}

variable "kube_state_metrics_resources" {
  description = "CPU/memory requests and limits for the Kube State Metrics Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "64Mi"
    }
  }
}

variable "loki_write_resources" {
  description = "CPU/memory requests and limits for the Loki write StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "256Mi"
    }
  }
}

variable "loki_read_resources" {
  description = "CPU/memory requests and limits for the Loki read StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "256Mi"
    }
  }
}

variable "loki_backend_resources" {
  description = "CPU/memory requests and limits for the Loki backend StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "256Mi"
    }
  }
}

variable "loki_standalone_resources" {
  description = "CPU/memory requests and limits for the Loki standalone StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "256Mi"
    }
  }
}

variable "mimir_write_resources" {
  description = "CPU/memory requests and limits for the Mimir write StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "512Mi"
    }
  }
}

variable "mimir_read_resources" {
  description = "CPU/memory requests and limits for the Mimir read StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "256Mi"
    }
  }
}

variable "mimir_backend_resources" {
  description = "CPU/memory requests and limits for the Mimir backend StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "50m"
      memory = "256Mi"
    }
  }
}

variable "mimir_standalone_resources" {
  description = "CPU/memory requests and limits for the Mimir standalone StatefulSet"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  # standalone runs all targets; combined estimate from split components
  default = {
    requests = {
      cpu    = "100m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "512Mi"
    }
  }
}

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

variable "tailscale_operator_manager_resources" {
  description = "CPU/memory requests and limits for the Tailscale Operator Manager Deployment"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "25m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "25m"
      memory = "128Mi"
    }
  }
}

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
