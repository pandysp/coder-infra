.PHONY: validate lint push-templates push-base-dev push-docker-dev

# --- Validation (GH #5: ensures Galaxy collections are installed first) ------

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

push-templates: push-base-dev push-docker-dev ## Push all Coder templates

push-base-dev: ## Push base-dev template to Coder
	tar -cvh -C templates/base-dev . | coder templates push base-dev -d - -y

push-docker-dev: ## Push docker-dev template to Coder
	tar -cvh -C templates/docker-dev . | coder templates push docker-dev -d - -y

# --- Provisioning ------------------------------------------------------------

verify: ## Run post-deploy health checks
	bash scripts/verify.sh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
