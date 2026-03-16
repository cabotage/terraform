# Cabotage on Minikube

Try out Cabotage locally with minikube.

## Quick start

```sh
make setup       # start minikube, configure DNS, deploy everything
make verify-dns  # check that it's working
```

> **Note:** `make setup` will prompt for your sudo password to configure
> DNS resolution (`/etc/resolver/minikube-cabotage`).

That's it. Open https://cabotage.ingress.cabotage.dev/ in your browser
(accept the self-signed cert warning).

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- openssl

## Make targets

**General:**

| Target | Description |
|---|---|
| `make setup` | Full setup: start minikube, enable addons, configure DNS, deploy. Will prompt for sudo. |
| `make clean` | Remove everything: cluster, DNS config, CA, state files. Requires sudo. |
| `make help` | List all targets. |

**Terraform:**

| Target | Description |
|---|---|
| `make plan` | Run `terraform plan`. |
| `make apply` | Run `terraform apply` (interactive). |
| `make auto-apply` | Run `terraform apply -auto-approve`. |
| `make destroy` | Run `terraform destroy`. |

**Internal** (called by `setup`, but can be run individually):

| Target | Description |
|---|---|
| `make start` | Generate root CA (if needed) and start minikube. |
| `make addons` | Enable required minikube addons (`ingress-dns`). |
| `make dns` | Configure macOS DNS resolver. Requires sudo. |
| `make verify-dns` | Verify DNS resolution and app connectivity. |

---

## How it works

### Root CA

`make start` generates a root CA in `.secrets/` (if not already present)
and copies it to `~/.minikube/certs/`. The `--embed-certs` flag tells
minikube to install it into the node's trust store so containerd trusts
the internal registry.

### DNS

The `ingress-dns` minikube addon runs a DNS server that resolves Ingress
hostnames to the minikube node IP. `make dns` creates
`/etc/resolver/minikube-cabotage` so macOS routes
`*.ingress.cabotage.dev` lookups to that DNS server.

### Networking

Traefik runs with `hostNetwork: true`, binding ports 80/443 directly on
the minikube node. This means `ingress-dns` responses point to the right
place — no `minikube tunnel` needed.

### What's different from production?

| Setting | Minikube | Production |
|---|---|---|
| `traefik_host_network` | `true` | `false` (AWS NLB) |
| `enable_pebble_letsencrypt` | `true` | `false` (real Let's Encrypt) |
| `vault_dev_auto_unseal` | `true` | `false` (AWS KMS) |
| `security_confirmable` | `false` | `true` |
| `registry_verify` | CA cert path | `"True"` (system trust) |
