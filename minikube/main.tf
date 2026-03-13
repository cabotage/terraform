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
  config_context = "minikube"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

module "cabotage" {
  source = "../cabotage"

  cluster_identifier        = "minikube"
  kube_context              = "minikube"
  cabotage_app_image        = "ghcr.io/cabotage/cabotage-app:2026.3.13-0"
  secrets_dir               = abspath("${path.module}/.secrets")
  enable_pebble_letsencrypt = true
  forwarded_headers_cidrs   = ["10.96.0.0/12", "10.244.0.0/16"]
  proxy_protocol_cidrs      = ["10.96.0.0/12", "10.244.0.0/16"]
  traefik_replicas          = 1
  cabotage_app_hostname     = "cabotage.ingress.cabotage.dev"
  cabotage_ingress_domain   = "ingress.cabotage.dev"
  vault_dev_auto_unseal     = true
}
