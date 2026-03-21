PROFILE          ?= minikube-cabotage
MINIKUBE         := minikube -p $(PROFILE)
MINIKUBE_CPUS    ?= 6
MINIKUBE_MEMORY  ?= 16000
SECRETS_DIR      ?= .secrets
TF_WORKSPACE     ?= default
MINIKUBE_IP      ?= $(shell $(MINIKUBE) ip 2>/dev/null || echo 192.168.49.2)
RESOLVER_FILE    := /etc/resolver/minikube-cabotage
MINIKUBE_CERT    := $(HOME)/.minikube/certs/$(PROFILE)-ca.pem

.DEFAULT_GOAL := help

.PHONY: setup clean help plan apply auto-apply destroy start addons dns verify-dns

##@ General

setup: start addons dns auto-apply ## Full setup (will prompt for sudo)
	@echo ""
	@echo "Done! Try: make verify-dns"

clean: destroy ## Remove everything (requires sudo)
	$(MINIKUBE) delete
	@echo "NOTE: sudo is required to remove $(RESOLVER_FILE)"
	@sudo rm -f $(RESOLVER_FILE)
	@rm -f $(MINIKUBE_CERT)
	@rm -rf $(SECRETS_DIR)
	@rm -f ca.$(TF_WORKSPACE).crt ca.$(TF_WORKSPACE).srl
	@rm -f terraform.tfstate terraform.tfstate.backup
	@rm -rf .terraform .terraform.lock.hcl
	@echo "Cleaned up."

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; section = ""} \
		/^##@/ { section = substr($$0, 5); next } \
		/^[a-zA-Z_-]+:.*## / { printf "%s  \033[36m%-14s\033[0m %s\n", \
			(section != prev ? "\n\033[1m" section ":\033[0m\n" : ""), $$1, $$2; prev = section }' \
		$(MAKEFILE_LIST)

##@ Terraform

plan: ## Run terraform plan
	terraform init -upgrade
	terraform plan

apply: ## Run terraform apply (interactive)
	terraform init -upgrade
	terraform apply

auto-apply: ## Run terraform apply -auto-approve
	terraform init -upgrade
	terraform apply -auto-approve

destroy: ## Run terraform destroy
	terraform destroy

##@ Internal

start: $(MINIKUBE_CERT) ## Generate root CA and start minikube
	$(MINIKUBE) start \
		--cpus $(MINIKUBE_CPUS) \
		--memory $(MINIKUBE_MEMORY) \
		--embed-certs \
		--container-runtime containerd

addons: ## Enable required minikube addons
	$(MINIKUBE) addons enable ingress-dns
	$(MINIKUBE) addons enable metrics-server
	$(MINIKUBE) addons enable registry

dns: ## Configure macOS DNS resolver (requires sudo)
	@echo "NOTE: sudo is required to write $(RESOLVER_FILE)"
	@echo "Configuring $(RESOLVER_FILE) -> $(MINIKUBE_IP)"
	@sudo mkdir -p /etc/resolver
	@printf 'domain ingress.cabotage.dev\nnameserver %s\nsearch_order 1\ntimeout 5\n' "$(MINIKUBE_IP)" \
		| sudo tee $(RESOLVER_FILE) > /dev/null

verify-dns: ## Verify DNS and app connectivity
	@echo "--- DNS ---"
	@dig @$(MINIKUBE_IP) cabotage.ingress.cabotage.dev +short
	@echo "--- App ---"
	@curl -sk -o /dev/null -w 'https://cabotage.ingress.cabotage.dev/ -> %{http_code}\n' \
		https://cabotage.ingress.cabotage.dev/

# --- File targets ---

$(SECRETS_DIR)/$(TF_WORKSPACE)/ca.key ca.$(TF_WORKSPACE).crt:
	@echo "Generating root CA..."
	@mkdir -p $(SECRETS_DIR)/$(TF_WORKSPACE)
	openssl ecparam -genkey -name prime256v1 -noout -out $(SECRETS_DIR)/$(TF_WORKSPACE)/ca.key 2>/dev/null
	openssl req -new -x509 \
		-key $(SECRETS_DIR)/$(TF_WORKSPACE)/ca.key \
		-out ca.$(TF_WORKSPACE).crt \
		-days 3650 \
		-subj "/CN=$(PROFILE) Cabotage Root CA" \
		-addext "basicConstraints=critical,CA:TRUE" \
		-addext "keyUsage=critical,keyCertSign,cRLSign"
	chmod 600 $(SECRETS_DIR)/$(TF_WORKSPACE)/ca.key

$(MINIKUBE_CERT): ca.$(TF_WORKSPACE).crt
	@mkdir -p $(HOME)/.minikube/certs
	cp ca.$(TF_WORKSPACE).crt $(MINIKUBE_CERT)
	@echo "CA cert copied to $(MINIKUBE_CERT)"
