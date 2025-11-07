# Makefile for Cloudflare DNS Core Stack
# Provides convenience targets for common Terragrunt operations

.PHONY: help cloudflare-env export-to-terraform import-to-terraform init plan apply destroy fmt validate clean unlock

help:
	@echo "Available targets:"
	@echo "  cloudflare-env        - Load Cloudflare credentials from 1Password"
	@echo "  export-to-terraform   - Export Cloudflare DNS records to terraform.tfvars"
	@echo "  import-to-terraform   - Import Cloudflare DNS records into Terraform state"
	@echo "  init                  - Initialize Terragrunt/Terraform"
	@echo "  plan                  - Run terragrunt plan"
	@echo "  apply                 - Run terragrunt apply"
	@echo "  destroy               - Run terragrunt destroy"
	@echo "  fmt                   - Format Terraform files"
	@echo "  validate              - Validate Terraform configuration"
	@echo "  unlock                - Force unlock state (Usage: make unlock LOCK_ID=<id>)"
	@echo "  clean                 - Remove .terraform and .terragrunt-cache"

cloudflare-env:
	@echo "Run this command to load Cloudflare credentials:"
	@echo ""
	@echo "  eval \"\$$(../setup-cloudflare-env.sh)\""
	@echo ""
	@echo "Or source it directly:"
	@echo ""
	@echo "  source ../setup-cloudflare-env.sh"
	@echo ""

export-to-terraform:
	@bash -c ' \
		if [ -z "$$CLOUDFLARE_API_TOKEN" ]; then \
			echo "Cloudflare credentials not loaded. Loading from 1Password..."; \
			eval "$$(../setup-cloudflare-env.sh 2>/dev/null)"; \
		fi; \
		../export-to-terraform.sh publiccloudexperiments.net tfvars \
	'

import-to-terraform:
	@bash -c ' \
		if [ -z "$$CLOUDFLARE_API_TOKEN" ]; then \
			echo "Cloudflare credentials not loaded. Loading from 1Password..."; \
			echo ""; \
			eval "$$(../setup-cloudflare-env.sh 2>/dev/null)"; \
		fi; \
		echo "This will import Cloudflare DNS records into Terraform state."; \
		echo "Make sure you have run '\''make init'\'' first!"; \
		echo ""; \
		read -p "Continue? [y/N] " -n 1 -r; \
		echo; \
		if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
			cd .. && ./import-to-terraform.sh publiccloudexperiments.net dns-core; \
		else \
			echo "Import cancelled."; \
		fi \
	'

init:
	terragrunt init

plan:
	@bash -c ' \
		if [ -z "$$CLOUDFLARE_API_TOKEN" ]; then \
			echo "Cloudflare credentials not loaded. Loading from 1Password..."; \
			echo ""; \
			eval "$$(../setup-cloudflare-env.sh 2>/dev/null)"; \
		fi; \
		terragrunt plan \
	'

apply:
	@bash -c ' \
		if [ -z "$$CLOUDFLARE_API_TOKEN" ]; then \
			echo "Cloudflare credentials not loaded. Loading from 1Password..."; \
			echo ""; \
			eval "$$(../setup-cloudflare-env.sh 2>/dev/null)"; \
		fi; \
		terragrunt apply \
	'

destroy:
	terragrunt destroy

fmt:
	terraform fmt -recursive .

validate:
	@bash -c ' \
		if [ -z "$$CLOUDFLARE_API_TOKEN" ]; then \
			echo "Cloudflare credentials not loaded. Loading from 1Password..."; \
			echo ""; \
			eval "$$(../setup-cloudflare-env.sh 2>/dev/null)"; \
		fi; \
		terragrunt validate \
	'

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
