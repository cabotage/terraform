# cabotage-eks

Terraform module that provisions an opinionated EKS cluster for [Cabotage](https://github.com/cabotage/cabotage-app), including the surrounding VPC, storage, load balancing, and DNS infrastructure.

## What it creates

- **VPC** — Public/private subnets across specified AZs, NAT gateway(s), DNS hostnames enabled. Uses `terraform-aws-modules/vpc/aws`.
- **EKS cluster** — Managed control plane and node groups via `terraform-aws-modules/eks/aws`. Includes core addons: CoreDNS, kube-proxy, VPC CNI (with prefix delegation and network policy support), and EKS Pod Identity Agent.
- **EBS CSI driver** — Installed as an EKS addon with an IRSA role. Creates a `gp3` StorageClass (default).
- **AWS Load Balancer Controller** — Helm chart + IRSA role for provisioning ALBs/NLBs via Kubernetes ingress/service resources.
- **Metrics Server** — Helm chart for pod/node resource metrics (HPA, `kubectl top`).
- **NodeLocal DNSCache** — DaemonSet DNS cache on each node. Optionally configured for ingress hairpin routing.
- **Karpenter** (optional) — Dynamic node provisioning with dedicated `standard`, `preview`, and `backing-services` NodePools.
- **Ingress hairpin routing** (optional) — For specified domains, NodeLocal DNS resolves `*.domain` to an in-cluster ingress controller ClusterIP, allowing pod-to-pod traffic to stay inside the cluster instead of looping through an external load balancer. Requires configuring `ingress_hairpin_domains`.
- **Vault auto-unseal** (optional) — KMS key + IRSA role that lets Vault auto-unseal using AWS KMS. Enable with `enable_vault_auto_unseal`.
- **Tailscale subnet router** (optional) — EC2-based subnet router that advertises VPC routes to a Tailscale tailnet, enabling private access to the EKS API server without exposing it publicly. Authenticates via Tailscale Workload Identity Federation (no static keys). Enable with `enable_tailscale_subnet_router`.

## Usage

```hcl
module "cabotage_eks" {
  source = "./modules/cabotage-eks"

  project_name       = "cabotage"
  cluster_name       = "cabotage-prod"
  availability_zones = ["us-east-2a", "us-east-2b", "us-east-2c"]

  private_subnet_cidrs = ["10.16.0.0/19", "10.16.32.0/19", "10.16.64.0/19"]
  public_subnet_cidrs  = ["10.16.96.0/24", "10.16.97.0/24", "10.16.98.0/24"]
  vpc_cidr             = "10.16.0.0/12"

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

  # Optional: VPC flow logs
  enable_vpc_flow_logs = true

  # Optional: restrict EKS public endpoint to specific CIDRs (SOC2)
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

  # Optional: Tailscale subnet router for private EKS access
  enable_tailscale_subnet_router        = true
  tailscale_workload_identity_client_id = "your-client-id"
  tailscale_workload_identity_audience  = "api.tailscale.com/your-client-id"
}
```

## Tailscale subnet router

The subnet router allows access to the EKS private API endpoint via Tailscale, eliminating the need for a public endpoint. It uses [Tailscale Workload Identity Federation](https://tailscale.com/docs/features/workload-identity-federation) to authenticate — no static auth keys or secrets to rotate.

### Setup

1. **Enable outbound web identity federation** on your AWS account (if not already enabled).

2. **Find your AWS STS issuer URL** by decoding a web identity token:

   IAM -> Account Settings -> Outbound Identity Federation -> Token Issuer URL

3. **First apply** — enable the subnet router without workload identity to create the IAM role:

   ```hcl
   enable_tailscale_subnet_router = true
   ```

   Grab the `tailscale_subnet_router_role_arn` output.

4. **Create a trust credential in Tailscale admin** → Trust Credentials → New:
   - Type: **OpenID Connect**
   - Issuer: **AWS**
   - Issuer URL: the URL from step 2
   - Subject: the `tailscale_subnet_router_role_arn` output from step 3
   - Scopes: **Devices > Core: Write**, **Devices > Routes: Write**, **Keys > Auth Keys: Write**

5. **Second apply** with the client ID and audience from the trust credential:

   ```hcl
   enable_tailscale_subnet_router        = true
   tailscale_workload_identity_client_id = "your-client-id"
   tailscale_workload_identity_audience  = "api.tailscale.com/your-client-id"
   ```

6. **Configure Tailscale ACLs** for auto-approval and access control. The `tailscale_setup` output provides a ready-to-use snippet:

   ```bash
   terraform output tailscale_setup
   ```

   Add the `autoApprovers` and `acls` sections to your Tailscale ACL policy.

7. **Configure split DNS** in Tailscale admin → DNS → Nameservers → Restricted nameservers:
   - Domain: `eks.amazonaws.com`
   - Nameserver: the VPC DNS resolver (VPC CIDR base + 2, shown in `tailscale_setup.split_dns.nameserver`)
   - For multi-cluster setups, add each cluster's VPC DNS resolver as an additional nameserver for the same domain. Each resolver only responds for its own cluster's endpoint, and non-overlapping VPC CIDRs ensure queries route through the correct subnet router.

### Accessing the cluster

Once set up, access is transparent. Tailscale runs in the background, the subnet router advertises VPC routes, and split DNS resolves the EKS endpoint to private IPs.

```bash
aws eks update-kubeconfig --name your-cluster --region us-east-1
kubectl get nodes
```

### GitHub Actions

Use the [Tailscale GitHub Action](https://github.com/tailscale/github-action) to connect CI runners to the tailnet:

```yaml
- uses: tailscale/github-action@v3
  with:
    oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
    tags: tag:ci

- run: |
    aws eks update-kubeconfig --name your-cluster --region us-east-1
    kubectl get nodes
```

### VPC CIDR planning

Each cluster's VPC CIDR must be unique if multiple clusters share the same tailnet — Tailscale can't distinguish overlapping routes from different subnet routers. Use non-overlapping `/12` blocks in the `10.0.0.0/8` space:

```
10.16.0.0/12   - staging   (~1M IPs)
10.32.0.0/12   - prod      (~1M IPs)
10.48.0.0/12   - dev       (~1M IPs)
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
| `cluster_endpoint_public_access_cidrs` | CIDR blocks allowed to access the EKS public endpoint | `list(string)` | `["0.0.0.0/0"]` |
| `enable_prefix_delegation` | VPC CNI prefix delegation for higher pod density | `bool` | `true` |
| `enable_network_policy` | Native VPC CNI network policy enforcement | `bool` | `true` |
| `node_groups` | Map of EKS managed node group definitions | `any` | 1 default group (`m8g.xlarge`, 2–10 nodes) |
| `node_group_disk_size` | Root EBS volume size in GiB for node groups | `number` | `20` |
| `gp3_as_default_storage_class` | Set gp3 StorageClass as cluster default | `bool` | `true` |
| `aws_lb_controller_chart_version` | Helm chart version for AWS LB Controller | `string` | `"3.1.0"` |
| `metrics_server_chart_version` | Helm chart version for Metrics Server | `string` | `"3.13.0"` |
| `node_local_dns_chart_version` | Helm chart version for NodeLocal DNSCache | `string` | `"2.7.0"` |
| `ingress_hairpin_domains` | Domains to hairpin via in-cluster ingress | `list(string)` | `[]` |
| `ingress_controller_namespace` | Namespace of the ingress controller | `string` | `"traefik"` |
| `ingress_controller_selector` | Label selector for ingress controller pods | `map(string)` | `{"app.kubernetes.io/name": "traefik"}` |
| `enable_vault_auto_unseal` | Create KMS key + IRSA role for Vault auto-unseal | `bool` | `false` |
| `vault_namespace` | Kubernetes namespace where Vault runs | `string` | `"cabotage"` |
| `enable_karpenter` | Deploy Karpenter for dynamic node provisioning | `bool` | `false` |
| `karpenter_ami_alias_version` | AL2023 AMI alias version for Karpenter nodes | `string` | `"latest"` |
| `karpenter_standard_instance_families` | Instance families for the standard Karpenter node pool | `list(string)` | `["m8g", "c8g", "r8g"]` |
| `karpenter_standard_instance_sizes` | Allowed instance sizes for the standard Karpenter node pool | `list(string)` | `["large", "xlarge", "2xlarge", "4xlarge"]` |
| `karpenter_standard_cpu_limit` | Maximum total vCPUs for the standard node pool | `number` | `100` |
| `karpenter_preview_instance_families` | Instance families for the preview Karpenter node pool | `list(string)` | `["m8g", "c8g", "r8g"]` |
| `karpenter_preview_instance_sizes` | Allowed instance sizes for the preview Karpenter node pool | `list(string)` | `["medium", "large", "xlarge", "2xlarge"]` |
| `karpenter_preview_cpu_limit` | Maximum total vCPUs for the preview node pool | `number` | `50` |
| `karpenter_backing_services_pool_name` | Name of the dedicated Karpenter node pool for Postgres/Redis workloads | `string` | `"backing-services"` |
| `karpenter_backing_services_instance_families` | Instance families for the backing-services Karpenter node pool | `list(string)` | `["m8g", "r8g"]` |
| `karpenter_backing_services_instance_sizes` | Allowed instance sizes for the backing-services Karpenter node pool | `list(string)` | `["xlarge", "2xlarge"]` |
| `karpenter_backing_services_cpu_limit` | Maximum total vCPUs for the backing-services node pool | `number` | `50` |
| `enable_s3_storage` | Create S3 buckets and IAM for registry, loki, mimir, and CNPG backups | `bool` | `false` |
| `s3_bucket_prefix` | Prefix for S3 bucket names | `string` | `""` |
| `tenant_postgres_backup_service_account_name` | ServiceAccount name trusted for tenant CNPG backups across tenant namespaces when S3 storage is enabled | `string` | `"cnpg-backups"` |
| `tenant_postgres_backup_allowed_namespaces` | Namespaces allowed to assume the tenant CNPG backup IRSA role | `list(string)` | `["*"]` |
| `kms_key_administrators` | IAM ARNs for KMS key administrators | `list(string)` | `[]` |
| `enabled_log_types` | EKS control plane log types to enable | `list(string)` | `[]` |
| `cloudwatch_log_group_retention_in_days` | Retention for EKS control plane logs | `number` | `90` |
| `enable_cluster_creator_admin_permissions` | Grant current caller admin access to EKS | `bool` | `true` |
| `access_entries` | Map of access entries for the EKS cluster | `any` | `{}` |
| `enable_vpc_flow_logs` | Enable VPC flow logs to CloudWatch | `bool` | `false` |
| `vpc_flow_log_retention_in_days` | Retention for VPC flow log events | `number` | `365` |
| `vpc_flow_log_traffic_type` | Traffic type to capture (ACCEPT, REJECT, ALL) | `string` | `"ALL"` |
| `enable_tailscale_subnet_router` | Deploy EC2 Tailscale subnet router for private VPC access | `bool` | `false` |
| `tailscale_workload_identity_client_id` | Tailscale OIDC client ID (from Trust Credentials) | `string` | `""` |
| `tailscale_workload_identity_audience` | Tailscale OIDC audience (from Trust Credentials) | `string` | `""` |
| `tailscale_subnet_router_tags` | Tailscale ACL tags for the subnet router | `list(string)` | `["tag:subnet-router"]` |
| `tailscale_subnet_router_instance_type` | EC2 instance type for the subnet router | `string` | `"t4g.nano"` |
| `tailscale_subnet_router_hostname` | Tailscale hostname prefix for the subnet router | `string` | `"eks-subnet-router"` |
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
| `s3_storage` | S3 storage configuration, including infra and tenant CNPG backup IAM details (null if disabled) |
| `node_group_autoscaling_group_names` | Map of node group names to ASG names |
| `tailscale_subnet_router_autoscaling_group_name` | Subnet router ASG name (empty if disabled) |
| `tailscale_subnet_router_role_arn` | IAM role ARN for the subnet router (use as Subject in Tailscale trust credential) |
| `tailscale_setup` | Tailscale configuration guide: trust credential settings, ACL snippet, and split DNS config (null if disabled) |
| `karpenter_backing_services_pool_name` | Name of the dedicated Karpenter node pool for backing services |
| `vpc_cidr` | CIDR block of the VPC |
| `vpc_id` | VPC ID |
| `private_subnet_ids` | Private subnet IDs |
| `public_subnet_ids` | Public subnet IDs |
