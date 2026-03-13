terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
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

provider "aws" {
  region = "us-east-1"
}

data "aws_eks_cluster" "this" {
  name = "dev-astral"
}

data "aws_eks_cluster_auth" "this" {
  name = "dev-astral"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "arn:aws:eks:us-east-1:318662118699:cluster/dev-astral"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "arn:aws:eks:us-east-1:318662118699:cluster/dev-astral"
  }
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "arn:aws:eks:us-east-1:318662118699:cluster/dev-astral"
}

module "cabotage" {
  source = "../cabotage"

  cluster_identifier      = "arn:aws:eks:us-east-1:318662118699:cluster/dev-astral"
  kube_context            = "arn:aws:eks:us-east-1:318662118699:cluster/dev-astral"
  cabotage_app_image      = "ghcr.io/cabotage/cabotage-app:2026.3.13-0"
  secrets_dir             = abspath("${path.module}/.secrets")
  forwarded_headers_cidrs = ["10.0.0.0/16", "10.100.0.0/16"]
  proxy_protocol_cidrs    = ["10.0.0.0/16"]
  traefik_replicas        = 6
  traefik_aws_lb          = true
  registry_replicas       = 6
  consul_local_port       = 18501
  cabotage_app_hostname   = "astral-dev.cabotage.io"
  cabotage_ingress_domain = "cabotage.app"
  github_app_id           = 3056610
}
