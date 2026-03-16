terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}
