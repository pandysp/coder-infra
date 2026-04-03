.PHONY: validate lint push-templates push-base-dev push-docker-dev

# --- Validation --------------------------------------------------------------

validate: validate-terraform validate-ansible ## Run all validation checks

validate-terraform: ## Validate Terraform/OpenTofu configs
	cd terraform && tofu init -backend=false && tofu validate
	cd templates/base-dev && tofu init -backend=false && tofu validate
	cd templates/docker-dev && tofu init -backend=false && tofu validate

validate-ansible: ## Validate Ansible playbook (installs Galaxy deps first)
	cd ansible && ansible-galaxy collection install -r requirements.yml
	cd ansible && ansible-playbook playbook.yml --syntax-check -i inventory/hosts.ini.example

lint: validate ## Alias for validate

# --- Template push (dereferences symlinks for shared module) -----------------
# Clean .terraform to avoid uploading darwin provider binaries (~18MB) to the
# linux server. The Coder provisioner re-downloads the correct platform binaries.
# Template variables are read from terraform.tfvars (claude_setup_token is
# required for Claude Code auth in workspaces).

TFVARS := terraform/terraform.tfvars
SETUP_TOKEN := $(shell grep claude_setup_token $(TFVARS) 2>/dev/null | sed 's/.*= *"//;s/"//')
TEMPLATE_VARS := --variable "claude_setup_token=$(SETUP_TOKEN)" --variable "anthropic_api_key="

push-templates: push-base-dev push-docker-dev ## Push all Coder templates

push-base-dev: ## Push base-dev template to Coder
	rm -rf templates/base-dev/.terraform
	tar -cvh -C templates/base-dev . | coder templates push base-dev -d - -y $(TEMPLATE_VARS)

push-docker-dev: ## Push docker-dev template to Coder
	rm -rf templates/docker-dev/.terraform
	tar -cvh -C templates/docker-dev . | coder templates push docker-dev -d - -y $(TEMPLATE_VARS)

# --- Provisioning ------------------------------------------------------------

verify: ## Run post-deploy health checks
	bash scripts/verify.sh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
