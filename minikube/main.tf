terraform {
  required_version = ">= 1.5.7"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.1"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube-cabotage"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "minikube-cabotage"
  }
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "minikube-cabotage"
}

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

module "cabotage" {
  source = "../modules/cabotage"

  cluster_identifier        = "minikube"
  kube_context              = "minikube-cabotage"
  cabotage_app_image        = "ghcr.io/cabotage/cabotage-app:latest"
  secrets_dir               = abspath("${path.module}/.secrets")
  enable_pebble_letsencrypt = true
  forwarded_headers_cidrs   = ["10.96.0.0/12", "10.244.0.0/16"]
  proxy_protocol_cidrs      = ["10.96.0.0/12", "10.244.0.0/16"]
  # Lightweight single-node defaults. For a more production-like clustered
  # setup on minikube (requires a multi-node cluster, e.g.
  # `minikube start --nodes 3`), use:
  #
  #   rustfs_replicas          = 4
  #   rustfs_disks_per_replica = 4   # erasure coding (16 PVCs total)
  #   loki_standalone          = false  # separate read/write/backend StatefulSets
  #   mimir_standalone         = false
  #   consul_replicas          = 3   # raft quorum (requires anti-affinity zones)
  #   consul_storage_size      = "10Gi"
  #   vault_replicas           = 3
  #
  rustfs_replicas           = 1
  rustfs_disks_per_replica  = 1    # FS mode — no erasure coding
  loki_standalone           = true # single all-in-one process
  mimir_standalone          = true
  consul_replicas           = 1
  consul_storage_size       = "1Gi"
  vault_replicas            = 1
  traefik_replicas          = 1
  traefik_aws_lb            = false
  traefik_host_network      = true
  cabotage_app_hostname     = "cabotage.ingress.cabotage.dev"
  cabotage_ingress_domain   = "ingress.cabotage.dev"
  registry_verify           = "/var/run/secrets/cabotage.io/ca.crt"
  vault_dev_auto_unseal     = true
  security_confirmable      = false
  enable_gvisor             = true
}
