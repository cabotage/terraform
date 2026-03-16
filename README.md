# cabotage-infra

Terraform modules for deploying [Cabotage](https://github.com/cabotage/cabotage-app) — a PaaS for building, deploying, and managing containerized applications on Kubernetes.

## Modules

### [`cabotage-eks`](modules/cabotage-eks/)

Provisions an opinionated AWS EKS cluster with VPC, node groups, EBS CSI, AWS Load Balancer Controller, Metrics Server, NodeLocal DNSCache, and optional Vault KMS auto-unseal.

### [`cabotage`](modules/cabotage/)

Deploys the full Cabotage platform onto an existing Kubernetes cluster:

- **Ingress & TLS** — Traefik, cert-manager, internal PKI with offline root CA
- **Service discovery & secrets** — Consul, Vault (with KMS or dev auto-unseal)
- **Data stores** — PostgreSQL (CNPG), Redis, RustFS (S3-compatible object storage)
- **Application** — Cabotage web/worker/worker-beat, enrollment operator, container registry
- **Monitoring** — Alloy, Loki, Mimir

## Quick start

```hcl
module "cabotage_eks" {
  source = "./modules/cabotage-eks"

  project_name       = "cabotage"
  cluster_name       = "cabotage-prod"
  availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]

  private_subnet_cidrs = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
  public_subnet_cidrs  = ["10.0.96.0/24", "10.0.97.0/24", "10.0.98.0/24"]

  enable_vault_auto_unseal = true
}

module "cabotage" {
  source = "./modules/cabotage"

  cluster_identifier      = module.cabotage_eks.cluster_name
  kube_context            = "arn:aws:eks:us-east-2:123456789012:cluster/cabotage-prod"
  forwarded_headers_cidrs = ["10.0.0.0/16"]
  proxy_protocol_cidrs    = ["10.0.0.0/16"]
  cabotage_app_hostname   = "cabotage.example.com"

  traefik_aws_lb               = true
  vault_auto_unseal_kms_key_id = module.cabotage_eks.vault_unseal_kms_key_id
  vault_auto_unseal_role_arn   = module.cabotage_eks.vault_unseal_irsa_role_arn
  vault_auto_unseal_region     = "us-east-2"
}
```

### Local development with Minikube

```sh
minikube start --cpus 6 --memory 16000 --container-runtime containerd
minikube addons enable ingress-dns
minikube addons enable registry
cd clusters/minikube/cabotage
terraform init -upgrade
terraform apply
```

## Prerequisites

- Terraform >= 1.5.7
- `kubectl` configured for the target cluster
- `openssl` available locally (for root CA generation)

## License

[MIT](LICENSE)
