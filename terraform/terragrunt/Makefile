# Makefile for Terragrunt operations
# Simplifies common commands

# Color output
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Check if tools are installed
TOFU := $(shell command -v tofu 2> /dev/null)
TERRAFORM := $(shell command -v terraform 2> /dev/null)
TFLINT := $(shell command -v tflint 2> /dev/null)

# Use tofu or terraform for formatting
FMT_TOOL := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,))

# Default target
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo "Terragrunt Helper Commands"
	@echo "=========================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make setup                   # Configure Azure backend"
	@echo "  make app-a-init              # Initialize ps-az-sbx/app-a"
	@echo "  make subnet-calc-apim-init   # Initialize personal-sub/subnet-calc-internal-apim"
	@echo "  make subnet-calc-apim-plan   # Plan subnet calculator deployment"

.PHONY: setup
setup: ## Run setup script to configure environment (idempotent)
	@./setup-env.sh
	@echo ""
	@echo "$(YELLOW)Note: You still need to export the variables shown above.$(NC)"
	@echo "$(YELLOW)If you use direnv, copy those exports into $(PWD)/.envrc and run 'direnv allow'.$(NC)"
ifneq (,$(shell command -v az 2>/dev/null))
	@echo ""
	@echo "Detected Azure CLI. Available resource groups:"
	@az group list --query "[].{name:name,location:location}" -o table
	@echo ""
	@echo "You can populate TF_BACKEND_RG with one of the names above."
else
	@echo ""
	@echo "$(YELLOW)Azure CLI not detected; skipping resource group listing.$(NC)"
endif

.PHONY: check-terragrunt
check-terragrunt: ## Check if terragrunt is installed
	@if ! command -v terragrunt &>/dev/null; then \
		echo "$(YELLOW)❌ terragrunt is not installed$(NC)"; \
		echo ""; \
		echo "Install with:"; \
		echo "  brew install terragrunt"; \
		echo "  # or"; \
		echo "  brew tap gruntwork-io/terragrunt && brew install terragrunt"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ terragrunt installed:$(NC) $$(terragrunt --version | head -1)"

.PHONY: check-tofu
check-tofu: ## Check if terraform or opentofu is installed
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo "$(YELLOW)❌ Neither OpenTofu nor Terraform is installed$(NC)"; \
		echo ""; \
		echo "Install with:"; \
		echo "  brew install opentofu"; \
		echo "  # or"; \
		echo "  brew install terraform"; \
		exit 1; \
	fi
	@if [ -n "$(TOFU)" ]; then \
		echo "$(GREEN)✓ OpenTofu installed:$(NC) $$(tofu version | head -1)"; \
	elif [ -n "$(TERRAFORM)" ]; then \
		echo "$(GREEN)✓ Terraform installed:$(NC) $$(terraform version | head -1)"; \
	fi

.PHONY: check-tflint
check-tflint: ## Check if tflint is installed
	@if [ -z "$(TFLINT)" ]; then \
		echo "$(YELLOW)Warning: tflint is not installed$(NC)"; \
		echo "Install with: brew install tflint"; \
		echo "Skipping linting..."; \
	fi

.PHONY: check-env
check-env: ## Check if required environment variables are set
	@echo "Checking environment variables..."
	@if [ -z "$$ARM_SUBSCRIPTION_ID" ]; then \
		echo "$(YELLOW)Missing: ARM_SUBSCRIPTION_ID$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$$ARM_TENANT_ID" ]; then \
		echo "$(YELLOW)Missing: ARM_TENANT_ID$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$$TF_BACKEND_RG" ]; then \
		echo "$(YELLOW)Missing: TF_BACKEND_RG$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$$TF_BACKEND_SA" ]; then \
		echo "$(YELLOW)Missing: TF_BACKEND_SA$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$$TF_BACKEND_CONTAINER" ]; then \
		echo "$(YELLOW)Missing: TF_BACKEND_CONTAINER$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ All required variables set$(NC)"

.PHONY: check-config
check-config: ## Check if terraform.tfvars is configured
	@if [ ! -f ps-az-sbx/app-a/terraform.tfvars ]; then \
		echo "$(YELLOW)❌ terraform.tfvars not found$(NC)"; \
		echo ""; \
		echo "Create it with:"; \
		echo "  cd ps-az-sbx/app-a"; \
		echo "  cp terraform.tfvars.example terraform.tfvars"; \
		echo "  # Edit terraform.tfvars with your sandbox resource group"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ terraform.tfvars exists$(NC)"

.PHONY: preflight
preflight: check-terragrunt check-tofu check-env check-config ## Check all prerequisites (terragrunt, tofu/terraform, env vars, config)
	@echo ""
	@echo "$(GREEN)✓ All checks passed! Ready to deploy.$(NC)"
	@echo ""
	@echo "Next steps:"
	@echo "  make app-a-init        # Initialize"
	@echo "  make app-a-plan        # Plan deployment"
	@echo "  make app-a-apply       # Deploy"

# Pluralsight Azure Sandbox app-a targets
.PHONY: app-a-init
app-a-init: check-terragrunt check-env ## Initialize ps-az-sbx/app-a
	@cd ps-az-sbx/app-a && terragrunt init -upgrade

.PHONY: app-a-plan
app-a-plan: check-terragrunt check-env ## Plan ps-az-sbx/app-a
	@cd ps-az-sbx/app-a && terragrunt init -upgrade && terragrunt plan

.PHONY: app-a-apply
app-a-apply: check-terragrunt check-env ## Apply ps-az-sbx/app-a
	@cd ps-az-sbx/app-a && terragrunt init -upgrade && terragrunt apply

.PHONY: app-a-destroy
app-a-destroy: check-terragrunt check-env ## Destroy ps-az-sbx/app-a
	@cd ps-az-sbx/app-a && terragrunt destroy

.PHONY: app-a-output
app-a-output: check-terragrunt check-env ## Show outputs for ps-az-sbx/app-a
	@cd ps-az-sbx/app-a && terragrunt output

.PHONY: app-a-clean
app-a-clean: ## Clean ps-az-sbx/app-a cached files
	@cd ps-az-sbx/app-a && rm -rf .terraform .terragrunt-cache
	@echo "$(GREEN)✓ Cleaned ps-az-sbx/app-a$(NC)"

# Personal subscription subnet-calc-internal-apim targets
.PHONY: subnet-calc-apim-init
subnet-calc-apim-init: check-terragrunt check-env ## Initialize personal-sub/subnet-calc-internal-apim
	@cd personal-sub/subnet-calc-internal-apim && terragrunt init -upgrade

.PHONY: subnet-calc-apim-plan
subnet-calc-apim-plan: check-terragrunt check-env ## Plan personal-sub/subnet-calc-internal-apim
	@cd personal-sub/subnet-calc-internal-apim && terragrunt init -upgrade && terragrunt plan

.PHONY: subnet-calc-apim-apply
subnet-calc-apim-apply: check-terragrunt check-env ## Apply personal-sub/subnet-calc-internal-apim
	@cd personal-sub/subnet-calc-internal-apim && terragrunt init -upgrade && terragrunt apply

.PHONY: subnet-calc-apim-destroy
subnet-calc-apim-destroy: check-terragrunt check-env ## Destroy personal-sub/subnet-calc-internal-apim
	@cd personal-sub/subnet-calc-internal-apim && terragrunt destroy

.PHONY: subnet-calc-apim-output
subnet-calc-apim-output: check-terragrunt check-env ## Show outputs for personal-sub/subnet-calc-internal-apim
	@cd personal-sub/subnet-calc-internal-apim && terragrunt output

.PHONY: subnet-calc-apim-clean
subnet-calc-apim-clean: ## Clean personal-sub/subnet-calc-internal-apim cached files
	@cd personal-sub/subnet-calc-internal-apim && rm -rf .terraform .terragrunt-cache
	@echo "$(GREEN)✓ Cleaned personal-sub/subnet-calc-internal-apim$(NC)"

# Format and validate
.PHONY: fmt format
fmt format: check-tofu ## Format all Terraform files
	@echo "$(YELLOW)Formatting all Terraform files...$(NC)"
	@$(FMT_TOOL) fmt -recursive .
	@echo "$(GREEN)✓ Formatting complete$(NC)"

.PHONY: fmt-check
fmt-check: check-tofu ## Check formatting without making changes
	@echo "$(YELLOW)Checking Terraform formatting...$(NC)"
	@if $(FMT_TOOL) fmt -check -recursive . 2>/dev/null; then \
		echo "$(GREEN)✓ All files are properly formatted$(NC)"; \
	else \
		echo "$(YELLOW)Some files need formatting. Run 'make fmt' to fix.$(NC)"; \
		exit 1; \
	fi

.PHONY: lint
lint: check-tflint ## Lint all Terraform files (excluding downloaded modules)
	@if [ -n "$(TFLINT)" ]; then \
		echo "$(YELLOW)Linting all Terraform files (excluding downloaded modules)...$(NC)"; \
		for dir in $$(find . -name "*.tf" -not -path "*/.terraform/*" -not -path "*/.terragrunt-cache/*" -exec dirname {} \; | sort -u); do \
			echo "  → Checking $$dir"; \
			(cd $$dir && \
			if [ ! -f .tflint.hcl ]; then \
				echo 'plugin "azurerm" {' > .tflint.hcl; \
				echo '  enabled = true' >> .tflint.hcl; \
				echo '  version = "0.29.0"' >> .tflint.hcl; \
				echo '  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"' >> .tflint.hcl; \
				echo '}' >> .tflint.hcl; \
			fi; \
			tflint) || true; \
		done; \
		echo "$(GREEN)✓ Linting complete$(NC)"; \
	fi

.PHONY: quality
quality: fmt-check lint ## Run all quality checks
	@echo "$(GREEN)✓ All quality checks passed$(NC)"

.PHONY: validate
validate: check-terragrunt ## Validate all Terraform configurations
	@echo "Validating ps-az-sbx/app-a..."
	@cd ps-az-sbx/app-a && terragrunt init -upgrade && terragrunt validate
	@echo "Validating personal-sub/subnet-calc-internal-apim..."
	@cd personal-sub/subnet-calc-internal-apim && terragrunt init -upgrade && terragrunt validate
	@echo "$(GREEN)✓ All configurations valid$(NC)"

# Clean all
.PHONY: clean
clean: app-a-clean subnet-calc-apim-clean ## Clean all cached files
	@echo "$(GREEN)✓ All cleaned$(NC)"
