# cabotage-infra

Terraform modules for deploying [Cabotage](https://github.com/cabotage/cabotage-app) — a PaaS for building, deploying, and managing containerized applications on Kubernetes.

## Modules

### [`cabotage-eks`](modules/cabotage-eks/)

Provisions an opinionated AWS EKS cluster with VPC, node groups, EBS CSI, AWS Load Balancer Controller, Metrics Server, NodeLocal DNSCache, and optional Vault KMS auto-unseal.

### [`cabotage`](modules/cabotage/)

Deploys the full Cabotage platform onto an existing Kubernetes cluster:

- **Ingress & TLS** — Traefik, cert-manager, internal PKI with offline root CA
- **Tailscale integration** — optional Tailscale operator for Tailnet-based ingress (Funnel)
- **Service discovery & secrets** — Consul, Vault (with KMS or dev auto-unseal)
- **Data stores** — PostgreSQL (CNPG), Redis, SeaweedFS (S3-compatible object storage)
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

### Tailscale ingress

The `cabotage` module can optionally deploy the [Tailscale Kubernetes operator](https://tailscale.com/kb/1236/kubernetes-operator) to expose tenant ingresses to their tailnets. It can also expose the Cabotage UI via Tailscale Funnel instead of (or alongside) a traditional load balancer.

Enable it by setting `enable_tailscale = true` and providing OAuth credentials:

```hcl
module "cabotage" {
  # ...existing config...

  enable_tailscale                       = true
  tailscale_tag_prefix                   = "cabotage"
  tailscale_operator_hostname            = "my-operator"
  tailscale_operator_oauth_client_id     = var.tailscale_operator_oauth_client_id
  tailscale_operator_oauth_client_secret = var.tailscale_operator_oauth_client_secret

  # Optionally expose the Cabotage UI via Tailscale Funnel
  enable_tailscale_ingress    = true
  cabotage_tailscale_hostname = "cabotage"
}
```

The operator is deployed via its official Helm chart. `tailscale_operator_hostname` sets the machine name the operator registers as on the tailnet (defaults to `"tailscale-operator"`). The Funnel ingress for the Cabotage UI is controlled separately via `enable_tailscale_ingress` and `cabotage_tailscale_hostname`. Custom operator and proxy images can be specified with `tailscale_operator_image`, `tailscale_operator_image_tag`, `tailscale_proxy_image`, and `tailscale_proxy_image_tag`.

### Local development with Minikube

See [`minikube/`](minikube/) for a ready-to-use setup.

## Prerequisites

- Terraform >= 1.5.7
- `kubectl` configured for the target cluster
- `openssl` available locally (for root CA generation)

## License

[MIT](LICENSE)
