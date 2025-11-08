# Makefile for Subnet Calculator Static Web Apps Stack
# Provides convenience targets for common Terragrunt operations

.DEFAULT_GOAL := help

.PHONY: help check-env import-stacks reconfigure init plan apply destroy fmt validate clean unlock

# Check required environment variables are set
check-env:
	@if [ -z "$$ARM_SUBSCRIPTION_ID" ] || [ -z "$$ARM_TENANT_ID" ] || [ -z "$$TF_BACKEND_RG" ] || [ -z "$$TF_BACKEND_SA" ] || [ -z "$$TF_BACKEND_CONTAINER" ]; then \
		echo "❌ Required environment variables not set."; \
		echo ""; \
		echo "Run the setup script from the terragrunt root:"; \
		echo "  cd ../../ && ./setup-env.sh --group rg-subnet-calc --ci"; \
		echo "  eval \"\$$(./setup-env.sh --group rg-subnet-calc --ci 2>&1 | grep '^export')\""; \
		echo ""; \
		echo "Or for interactive mode:"; \
		echo "  cd ../../ && ./setup-env.sh --group rg-subnet-calc"; \
		echo "  # Then export the variables shown"; \
		echo ""; \
		echo "Required variables:"; \
		echo "  - ARM_SUBSCRIPTION_ID"; \
		echo "  - ARM_TENANT_ID"; \
		echo "  - TF_BACKEND_RG"; \
		echo "  - TF_BACKEND_SA"; \
		echo "  - TF_BACKEND_CONTAINER"; \
		exit 1; \
	fi
	@echo "✓ Environment variables are set"

help:
	@echo "Available targets:"
	@echo ""
	@echo "Setup:"
	@echo "  check-env             - Verify environment variables are set"
	@echo "  reconfigure           - Clean cache and reinitialize (when switching projects)"
	@echo ""
	@echo "  Setup environment variables (Nushell):"
	@echo "    bash ../../setup-env.sh --group rg-subnet-calc --nushell --force | save -f /tmp/tf-env.nu"
	@echo "    source /tmp/tf-env.nu"
	@echo ""
	@echo "Import (one-time setup for existing resources):"
	@echo "  import-stacks         - Import all existing Azure resources using stack-based mapping"
	@echo ""
	@echo "Terraform:"
	@echo "  init                  - Initialize Terragrunt/Terraform"
	@echo "  plan                  - Run terragrunt plan"
	@echo "  apply                 - Run terragrunt apply"
	@echo "  destroy               - Run terragrunt destroy"
	@echo "  fmt                   - Format Terraform files"
	@echo "  validate              - Validate Terraform configuration"
	@echo ""
	@echo "Utilities:"
	@echo "  unlock                - Force unlock state (Usage: make unlock LOCK_ID=<id>)"
	@echo "  clean                 - Remove .terraform and .terragrunt-cache"

import-stacks:
	@./import-stacks.sh

reconfigure: clean
	@echo "Reconfiguring Terragrunt backend..."
	@echo ""
	@echo "Run setup-env.sh to configure for a different resource group:"
	@echo "  bash ../../setup-env.sh --group <resource-group> --nushell --force | save -f /tmp/tf-env.nu"
	@echo "  source /tmp/tf-env.nu"
	@echo ""
	@echo "Then run: make init"

init: check-env
	@terragrunt init

plan: check-env
	@terragrunt plan

apply: check-env
	@terragrunt apply

destroy: check-env
	@terragrunt destroy

fmt:
	@terraform fmt -recursive .

validate: check-env
	@terragrunt validate

LOCK ?= $(LOCK_ID)
ifeq ($(firstword $(MAKECMDGOALS)),unlock)
  EXTRA_GOALS := $(filter-out unlock,$(MAKECMDGOALS))
  ifneq ($(firstword $(EXTRA_GOALS)),)
    LOCK := $(firstword $(EXTRA_GOALS))
  endif
  ifndef LOCK
    LOCK :=
  endif
  ifneq ($(EXTRA_GOALS),)
    .PHONY: $(EXTRA_GOALS)
$(EXTRA_GOALS):
	@:
  endif
endif

unlock:
	@if [ -z "$(LOCK)" ]; then \
		echo "LOCK_ID is required. Usage: make unlock LOCK_ID=<id> or make unlock <id>"; \
		exit 1; \
	fi
	terragrunt force-unlock $(LOCK)

clean:
	rm -rf .terraform .terragrunt-cache
	@echo "Cleaned .terraform and .terragrunt-cache directories"
