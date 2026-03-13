terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}
