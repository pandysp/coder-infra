.PHONY: validate lint push-templates new-template

# --- Validation --------------------------------------------------------------

validate: validate-terraform validate-ansible ## Run all validation checks

validate-terraform: ## Validate Terraform/OpenTofu configs
	cd terraform && tofu init -backend=false && tofu validate
	cd templates/examples/base-dev && tofu init -backend=false && tofu validate

validate-ansible: ## Validate Ansible playbook (installs Galaxy deps first)
	cd ansible && ansible-galaxy collection install -r requirements.yml
	cd ansible && ansible-playbook playbook.yml --syntax-check -i inventory/hosts.ini.example

lint: validate ## Alias for validate

# --- Template push -----------------------------------------------------------
# Discovers templates dynamically: any templates/<name>/main.tf (excluding
# modules/ and examples/) is a pushable template. Copies the shared module
# into a temp dir so symlinks are not required for push.

TFVARS := terraform/terraform.tfvars
SETUP_TOKEN := $(shell grep claude_setup_token $(TFVARS) 2>/dev/null | sed 's/.*= *"//;s/"//')
TEMPLATE_VARS := --variable "claude_setup_token=$(SETUP_TOKEN)" --variable "anthropic_api_key="

TEMPLATE_DIRS := $(dir $(wildcard templates/*/main.tf))
TEMPLATE_NAMES := $(filter-out modules examples,$(notdir $(patsubst %/,%,$(TEMPLATE_DIRS))))

push-templates: $(addprefix push-,$(TEMPLATE_NAMES)) ## Push all active templates to Coder

push-%: ## Push a single template (e.g., make push-dev)
	@rm -rf /tmp/coder-tpl-$*
	@mkdir -p /tmp/coder-tpl-$*
	@cp -r templates/$*/* /tmp/coder-tpl-$*/
	@rm -rf /tmp/coder-tpl-$*/modules
	@cp -r templates/modules /tmp/coder-tpl-$*/modules
	@rm -rf /tmp/coder-tpl-$*/.terraform
	tar -c -C /tmp/coder-tpl-$* . | coder templates push $* -d - -y $(TEMPLATE_VARS)
	@rm -rf /tmp/coder-tpl-$*

new-template: ## Create a new template from the reference example
	@test -n "$(NAME)" || (echo "Usage: make new-template NAME=my-template" && exit 1)
	@test ! -d "templates/$(NAME)" || (echo "templates/$(NAME) already exists" && exit 1)
	cp -r templates/examples/base-dev templates/$(NAME)
	rm -f templates/$(NAME)/modules
	ln -s ../modules templates/$(NAME)/modules
	@echo "Created templates/$(NAME) — edit main.tf, then run: make push-$(NAME)"

# --- Provisioning ------------------------------------------------------------

verify: ## Run post-deploy health checks
	bash scripts/verify.sh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
