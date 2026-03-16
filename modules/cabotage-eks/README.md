# cabotage-eks

Terraform module that provisions an opinionated EKS cluster for [Cabotage](https://github.com/cabotage/cabotage-app), including the surrounding VPC, storage, load balancing, and DNS infrastructure.

## What it creates

- **VPC** — Public/private subnets across specified AZs, NAT gateway(s), DNS hostnames enabled. Uses `terraform-aws-modules/vpc/aws`.
- **EKS cluster** — Managed control plane and node groups via `terraform-aws-modules/eks/aws`. Includes core addons: CoreDNS, kube-proxy, VPC CNI (with prefix delegation and network policy support), and EKS Pod Identity Agent.
- **EBS CSI driver** — Installed as an EKS addon with an IRSA role. Creates a `gp3` StorageClass (default).
- **AWS Load Balancer Controller** — Helm chart + IRSA role for provisioning ALBs/NLBs via Kubernetes ingress/service resources.
- **Metrics Server** — Helm chart for pod/node resource metrics (HPA, `kubectl top`).
- **NodeLocal DNSCache** — DaemonSet DNS cache on each node. Optionally configured for ingress hairpin routing.
- **Ingress hairpin routing** (optional) — For specified domains, NodeLocal DNS resolves `*.domain` to an in-cluster ingress controller ClusterIP, allowing pod-to-pod traffic to stay inside the cluster instead of looping through an external load balancer. Requires configuring `ingress_hairpin_domains`.
- **Vault auto-unseal** (optional) — KMS key + IRSA role that lets Vault auto-unseal using AWS KMS. Enable with `enable_vault_auto_unseal`.

## Usage

```hcl
module "cabotage_eks" {
  source = "./modules/cabotage-eks"

  project_name       = "cabotage"
  cluster_name       = "cabotage-prod"
  availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]

  private_subnet_cidrs = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
  public_subnet_cidrs  = ["10.0.96.0/24", "10.0.97.0/24", "10.0.98.0/24"]

  single_nat_gateway = false # HA for production

  node_groups = {
    default = {
      instance_types = ["m8g.xlarge"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
    }
  }

  # Optional: hairpin routing for in-cluster TLS
  ingress_hairpin_domains = ["example.com"]

  # Optional: Vault KMS auto-unseal
  enable_vault_auto_unseal = true
}
```

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5.7 |
| AWS provider | >= 6.0 |
| Kubernetes provider | >= 2.20 |
| Helm provider | >= 2.10 |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `project_name` | Project name, applied as a tag to all resources | `string` | — |
| `cluster_name` | Name of the EKS cluster | `string` | — |
| `cluster_version` | Kubernetes version | `string` | `"1.35"` |
| `vpc_cidr` | CIDR block for the VPC | `string` | `"10.0.0.0/16"` |
| `availability_zones` | List of AZs | `list(string)` | — |
| `private_subnet_cidrs` | Private subnet CIDRs (one per AZ, /19 recommended) | `list(string)` | — |
| `public_subnet_cidrs` | Public subnet CIDRs (one per AZ) | `list(string)` | — |
| `single_nat_gateway` | Use a single NAT gateway (false for HA) | `bool` | `true` |
| `cluster_endpoint_public_access` | Enable public access to the EKS API endpoint | `bool` | `true` |
| `enable_prefix_delegation` | VPC CNI prefix delegation for higher pod density | `bool` | `true` |
| `enable_network_policy` | Native VPC CNI network policy enforcement | `bool` | `true` |
| `node_groups` | Map of EKS managed node group definitions | `any` | 1 default group (`m8g.xlarge`, 2–10 nodes) |
| `gp3_as_default_storage_class` | Set gp3 StorageClass as cluster default | `bool` | `true` |
| `aws_lb_controller_chart_version` | Helm chart version for AWS LB Controller | `string` | `"3.1.0"` |
| `metrics_server_chart_version` | Helm chart version for Metrics Server | `string` | `"3.13.0"` |
| `node_local_dns_chart_version` | Helm chart version for NodeLocal DNSCache | `string` | `"2.7.0"` |
| `ingress_hairpin_domains` | Domains to hairpin via in-cluster ingress | `list(string)` | `[]` |
| `ingress_controller_namespace` | Namespace of the ingress controller | `string` | `"traefik"` |
| `ingress_controller_selector` | Label selector for ingress controller pods | `map(string)` | `{"app.kubernetes.io/name": "traefik"}` |
| `enable_vault_auto_unseal` | Create KMS key + IRSA role for Vault auto-unseal | `bool` | `false` |
| `vault_namespace` | Kubernetes namespace where Vault runs | `string` | `"cabotage"` |
| `tags` | Additional tags for all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | Name of the EKS cluster |
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_certificate_authority_data` | Base64 cluster CA certificate |
| `cluster_version` | Kubernetes version |
| `cluster_oidc_provider_arn` | OIDC provider ARN for IRSA/Pod Identity |
| `vault_unseal_kms_key_id` | KMS key ID for Vault unseal (empty if disabled) |
| `vault_unseal_irsa_role_arn` | IRSA role ARN for Vault unseal (empty if disabled) |
| `vpc_id` | VPC ID |
| `private_subnet_ids` | Private subnet IDs |
| `public_subnet_ids` | Public subnet IDs |
