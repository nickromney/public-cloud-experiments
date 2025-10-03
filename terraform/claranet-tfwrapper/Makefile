# Makefile for tfwrapper operations
# Usage: make <stack> <action> <env> <region>
# Example: make platform plan dev uks

# Default values
ACCOUNT := akscourse
DEFAULT_ENV := dev
DEFAULT_REGION := uks
CLIENT_NAME := akscourse

# Color output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Region mappings (short to full)
REGION_MAP_uks := uksouth
REGION_MAP_ukw := ukwest
REGION_MAP_eun := northeurope
REGION_MAP_euw := westeurope
REGION_MAP_use := eastus
REGION_MAP_usw := westus
REGION_MAP_usw2 := westus2
REGION_MAP_eastus := eastus
REGION_MAP_westus2 := westus2

# Environment mappings (short to full if needed)
ENV_MAP_dev := dev
ENV_MAP_uat := uat
ENV_MAP_prod := prod
ENV_MAP_sbx := sbx
ENV_MAP_sandbox := sbx
ENV_MAP_shared := shared

# Check if tools are installed
TFWRAPPER := $(shell command -v tfwrapper 2> /dev/null)
TFLINT := $(shell command -v tflint 2> /dev/null)
TOFU := $(shell command -v tofu 2> /dev/null)
TERRAFORM := $(shell command -v terraform 2> /dev/null)

# Use tofu or terraform for formatting
FMT_TOOL := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,))

# Helper function to get full region name
get_region = $(or $(REGION_MAP_$(1)),$(1))

# Helper function to get full environment name
get_env = $(or $(ENV_MAP_$(1)),$(1))

# Validate prerequisites
check-tfwrapper:
	@if [ -z "$(TFWRAPPER)" ]; then \
		echo "$(RED)Error: tfwrapper is not installed$(NC)"; \
		echo "Install with: uv tool install claranet-tfwrapper"; \
		exit 1; \
	fi

check-fmt-tool:
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo "$(RED)Error: Neither tofu nor terraform is installed$(NC)"; \
		echo "Install OpenTofu with: brew install opentofu"; \
		exit 1; \
	fi

check-tflint:
	@if [ -z "$(TFLINT)" ]; then \
		echo "$(YELLOW)Warning: tflint is not installed$(NC)"; \
		echo "Install with: brew install tflint"; \
		echo "Skipping linting..."; \
	fi

# Validate configuration exists
check-config = \
	@if [ ! -f "conf/$(ACCOUNT)_$(call get_env,$(2))_$(call get_region,$(3))_$(1).yml" ]; then \
		echo "$(RED)Error: Configuration not found$(NC)"; \
		echo "Expected: conf/$(ACCOUNT)_$(call get_env,$(2))_$(call get_region,$(3))_$(1).yml"; \
		echo ""; \
		echo "Available configurations:"; \
		ls -1 conf/*.yml 2>/dev/null | sed 's|conf/||' | sed 's|.yml||' || echo "  None found"; \
		exit 1; \
	fi

# Validate stack directory exists for non-bootstrap operations
check-stack = \
	@if [ "$(4)" != "bootstrap" ] && [ ! -d "$(ACCOUNT)/$(call get_env,$(2))/$(call get_region,$(3))/$(1)" ]; then \
		echo "$(YELLOW)Warning: Stack directory not found$(NC)"; \
		echo "Directory: $(ACCOUNT)/$(call get_env,$(2))/$(call get_region,$(3))/$(1)"; \
		echo ""; \
		echo "Run bootstrap first:"; \
		echo "  make $(1) bootstrap $(2) $(3)"; \
		exit 1; \
	fi

# Generic tfwrapper command
define tfwrapper_cmd
	@echo "$(GREEN)Running: tfwrapper -a $(ACCOUNT) -e $(call get_env,$(2)) -r $(call get_region,$(3)) -s $(1) $(4)$(NC)"
	@tfwrapper -a $(ACCOUNT) -e $(call get_env,$(2)) -r $(call get_region,$(3)) -s $(1) $(4)
endef

# Help target
help:
	@echo "Terraform tfwrapper Makefile"
	@echo ""
	@echo "$(GREEN)Setup Commands:$(NC)"
	@echo "  make setup                     # Initial setup (Azure login check, state config)"
	@echo "  make generate-stack-config     # Generate stack config from current Azure context"
	@echo "                                # Usage: make generate-stack-config STACK=platform ENV=dev REGION=uks"
	@echo ""
	@echo "$(GREEN)Stack Commands:$(NC)"
	@echo "  make <stack> <action> <env> <region>"
	@echo ""
	@echo "Examples:"
	@echo "  make platform plan dev uks               # Plan platform stack in dev/uksouth"
	@echo "  make platform apply dev uks              # Apply platform stack in dev/uksouth"
	@echo "  make basic init uat ukw                  # Initialize basic stack in uat/ukwest"
	@echo "  make platform bootstrap dev uks          # Bootstrap new platform stack (auto-generates config)"
	@echo "  make ps-sandbox plan eastus              # Plan Pluralsight sandbox stack"
	@echo ""
	@echo "$(GREEN)Available actions:$(NC)"
	@echo "  bootstrap - Bootstrap a new stack from template (auto-generates config if missing)"
	@echo "  init      - Initialize Terraform/OpenTofu"
	@echo "  plan      - Show execution plan"
	@echo "  apply     - Apply changes"
	@echo "  destroy   - Destroy infrastructure"
	@echo "  output    - Show outputs"
	@echo "  refresh   - Refresh state"
	@echo ""
	@echo "$(GREEN)Quality Commands:$(NC)"
	@echo "  make fmt                       # Format all Terraform files"
	@echo "  make fmt-check                 # Check if files are formatted"
	@echo "  make lint                      # Run tflint on all files"
	@echo "  make quality                   # Run all quality checks"
	@echo "  make validate STACK=x ENV=y REGION=z  # Validate specific stack"
	@echo ""
	@echo "$(GREEN)Other Commands:$(NC)"
	@echo "  make list                      # List configured and deployed stacks"
	@echo "  make clean                     # Remove .terraform directories"
	@echo "  make unlock STACK=x ENV=y REGION=z  # Unlock state (tries auto-detect)"
	@echo "  make unlock STACK=x ENV=y REGION=z LOCK_ID=abc-123  # Unlock with specific ID from error"
	@echo ""
	@echo "$(YELLOW)Note:$(NC) Quality checks (fmt & lint) run automatically before 'plan' and 'apply'"
	@echo ""
	@echo "Environments: dev, uat, prod"
	@echo "Regions: uks (uksouth), ukw (ukwest), eun (northeurope), euw (westeurope)"
	@echo ""
	@echo "Current configurations:"
	@ls -1 conf/*.yml 2>/dev/null | grep -v template | sed 's|conf/||' | sed 's|.yml||' | sed 's|^|  |' || echo "  None found"

# Platform stack targets
platform: check-tfwrapper
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "$(RED)Error: No action specified$(NC)"; \
		echo "Usage: make platform <action> <env> <region>"; \
		echo "Example: make platform plan dev uks"; \
		exit 1; \
	fi

# Basic stack targets
basic: check-tfwrapper
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "$(RED)Error: No action specified$(NC)"; \
		echo "Usage: make basic <action> <env> <region>"; \
		echo "Example: make basic plan dev uks"; \
		exit 1; \
	fi

# Messaging stack targets (for Service Bus demos)
messaging: check-tfwrapper
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "$(RED)Error: No action specified$(NC)"; \
		echo "Usage: make messaging <action> <env> <region>"; \
		echo "Example: make messaging plan sbx eastus"; \
		exit 1; \
	fi

# Charity Azure Service Bus with shared namespace pattern
charity-asb: check-tfwrapper
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make charity-asb <action> <env> <region>"; \
		echo "Example: make charity-asb bootstrap shared uks  # Deploy shared namespace"; \
		echo "         make charity-asb plan dev uks       # Deploy dev topics"; \
		echo "         make charity-asb apply test uks     # Deploy test topics"; \
		exit 1; \
	fi

# Pluralsight AKS course target
ps-aks: check-tfwrapper
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make ps-aks <action> <env> <region>"; \
		echo "Example: make ps-aks bootstrap sbx eastus"; \
		echo "         make ps-aks plan sbx eastus"; \
		echo "         make ps-aks apply sbx eastus"; \
		exit 1; \
	fi
	$(eval ACCOUNT := ps-az-sbx)
	$(eval CLIENT_NAME := ps-sandbox)

# Sandbox-specific targets for Pluralsight Azure Sandbox
ps-sandbox: check-tfwrapper
	@echo "$(YELLOW)Setting up Pluralsight Azure Sandbox...$(NC)"
	@echo "Remember: Sandbox expires in 4 hours!"
	@echo ""
	@echo "Available regions: eastus, westus2"
	@echo "Environment: sbx (sandbox)"
	@echo ""
	@if [ -z "$(filter bootstrap init plan apply destroy output refresh,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make ps-sandbox <action> <region>"; \
		echo "Example: make ps-sandbox bootstrap eastus"; \
		echo "         make ps-sandbox plan eastus"; \
		echo "         make ps-sandbox apply eastus"; \
		exit 1; \
	fi


# Parse arguments once at the top level
STACK := $(word 1,$(MAKECMDGOALS))
ACTION := $(word 2,$(MAKECMDGOALS))
ENV := $(word 3,$(MAKECMDGOALS))
REGION := $(word 4,$(MAKECMDGOALS))

# Define valid actions
ACTIONS := bootstrap init plan apply destroy output refresh

# Quality checks before running terraform commands
define run_quality_checks
	@echo "$(YELLOW)Running quality checks...$(NC)"
	$(call format-code,$(1),$(2),$(3))
	$(call lint-code,$(1),$(2),$(3))
	@echo "$(GREEN)Quality checks complete$(NC)"
endef

# Format terraform code
define format-code
	@if [ -n "$(FMT_TOOL)" ]; then \
		echo "  → Formatting Terraform files..."; \
		cd $(ACCOUNT)/$(call get_env,$(2))/$(call get_region,$(3))/$(1) 2>/dev/null && \
		$(FMT_TOOL) fmt -recursive . || true; \
		cd templates/azure 2>/dev/null && \
		$(FMT_TOOL) fmt -recursive . || true; \
	fi
endef

# Lint terraform code
define lint-code
	@if [ -n "$(TFLINT)" ] && [ -d "$(ACCOUNT)/$(call get_env,$(2))/$(call get_region,$(3))/$(1)" ]; then \
		echo "  → Linting Terraform files..."; \
		cd $(ACCOUNT)/$(call get_env,$(2))/$(call get_region,$(3))/$(1) && \
		if [ ! -f .tflint.hcl ]; then \
			echo 'plugin "azurerm" {' > .tflint.hcl; \
			echo '  enabled = true' >> .tflint.hcl; \
			echo '  version = "0.29.0"' >> .tflint.hcl; \
			echo '  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"' >> .tflint.hcl; \
			echo '}' >> .tflint.hcl; \
		fi; \
		tflint || true; \
	fi
endef

# Generic action handler
define run_action
	$(if $(filter bootstrap,$@),$(call create-config-if-missing,$(STACK),$(ENV),$(REGION)))
	$(call check-config,$(STACK),$(ENV),$(REGION))
	$(if $(filter-out bootstrap,$@),$(call check-stack,$(STACK),$(ENV),$(REGION),$@))
	$(if $(filter plan apply,$@),$(call run_quality_checks,$(STACK),$(ENV),$(REGION)))
	$(if $(filter bootstrap,$@),@echo "$(YELLOW)Bootstrapping $(STACK) stack$(NC)")
	$(call tfwrapper_cmd,$(STACK),$(ENV),$(REGION),$(if $(filter bootstrap,$@),bootstrap azure/$(STACK),$@))
endef

# Auto-create config for bootstrap if missing
define create-config-if-missing
	@if [ ! -f "conf/$(ACCOUNT)_$(call get_env,$(2))_$(call get_region,$(3))_$(1).yml" ]; then \
		echo "$(YELLOW)Auto-generating stack configuration$(NC)"; \
		$(MAKE) generate-stack-config STACK=$(1) ENV=$(2) REGION=$(3); \
	fi
endef

# Pattern rule for all actions
$(ACTIONS):
	$(run_action)

# Prevent make from treating arguments as targets
dev uat prod sbx sandbox uks ukw eun euw use usw usw2 eastus westus2:
	@:

# Quick aliases for common operations
.PHONY: list
list:
	@echo "$(GREEN)Configured stacks:$(NC)"
	@echo ""
	@echo "Configuration files:"
	@ls -1 conf/*.yml 2>/dev/null | sed 's|conf/||' | sed 's|.yml||' | while read config; do \
		echo "  $$config"; \
	done || echo "  None found"
	@echo ""
	@echo "Deployed stacks:"
	@find $(ACCOUNT) -mindepth 3 -maxdepth 3 -type d 2>/dev/null | while read dir; do \
		echo "  $${dir#$(ACCOUNT)/}"; \
	done || echo "  None found"

.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning .terraform directories...$(NC)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleaned$(NC)"

# Format all Terraform files
.PHONY: fmt format
fmt format: check-fmt-tool
	@echo "$(YELLOW)Formatting all Terraform files...$(NC)"
	@$(FMT_TOOL) fmt -recursive .
	@echo "$(GREEN)Formatting complete$(NC)"

# Check formatting without making changes
.PHONY: fmt-check
fmt-check: check-fmt-tool
	@echo "$(YELLOW)Checking Terraform formatting...$(NC)"
	@if $(FMT_TOOL) fmt -check -recursive . 2>/dev/null; then \
		echo "$(GREEN)All files are properly formatted$(NC)"; \
	else \
		echo "$(RED)Some files need formatting. Run 'make fmt' to fix.$(NC)"; \
		exit 1; \
	fi

# Lint all Terraform files (excluding downloaded modules)
.PHONY: lint
lint: check-tflint
	@if [ -n "$(TFLINT)" ]; then \
		echo "$(YELLOW)Linting all Terraform files (excluding downloaded modules)...$(NC)"; \
		for dir in $$(find . -name "*.tf" -not -path "*/.terraform/*" -not -path "./terraform/reference/*" -exec dirname {} \; | sort -u); do \
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
		echo "$(GREEN)Linting complete$(NC)"; \
	fi

# Validate Terraform configuration
.PHONY: validate
validate: check-tfwrapper
	@if [ -z "$(STACK)" ] || [ -z "$(ENV)" ] || [ -z "$(REGION)" ]; then \
		echo "$(RED)Error: Missing parameters$(NC)"; \
		echo "Usage: make validate STACK=<stack> ENV=<env> REGION=<region>"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Validating $(STACK) stack configuration...$(NC)"
	$(call tfwrapper_cmd,$(STACK),$(ENV),$(REGION),validate)

# Combined quality check
.PHONY: quality
quality: fmt-check lint
	@echo "$(GREEN)All quality checks passed$(NC)"

# Unlock terraform state
.PHONY: unlock
unlock:
	@if [ -z "$(STACK)" ] || [ -z "$(ENV)" ] || [ -z "$(REGION)" ]; then \
		echo "$(RED)Error: Missing parameters$(NC)"; \
		echo "Usage: make unlock STACK=<stack> ENV=<env> REGION=<region> [LOCK_ID=<id>]"; \
		echo "Example: make unlock STACK=platform ENV=dev REGION=uks"; \
		echo "Example: make unlock STACK=platform ENV=dev REGION=uks LOCK_ID=abc-123-def"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Attempting to unlock state for $(STACK) stack...$(NC)"
	@if [ -n "$(LOCK_ID)" ]; then \
		echo "Using provided lock ID: $(LOCK_ID)"; \
		cd $(ACCOUNT)/$(ENV)/$(call get_region,$(REGION))/$(STACK) && \
		tofu force-unlock -force $(LOCK_ID); \
	else \
		echo "Checking for existing locks..."; \
		cd $(ACCOUNT)/$(ENV)/$(call get_region,$(REGION))/$(STACK) 2>/dev/null && \
		if tofu show -json 2>&1 | grep -q "state blob is already locked"; then \
			FOUND_ID=$$(tofu show -json 2>&1 | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1); \
			if [ -n "$$FOUND_ID" ]; then \
				echo "Found lock ID: $$FOUND_ID"; \
				tofu force-unlock -force $$FOUND_ID; \
			else \
				echo "$(RED)Could not find lock ID automatically$(NC)"; \
				echo "Check the error output above for the lock ID and run:"; \
				echo "  make unlock STACK=$(STACK) ENV=$(ENV) REGION=$(REGION) LOCK_ID=<id>"; \
				exit 1; \
			fi; \
		else \
			echo "$(GREEN)No locks found or state is already unlocked$(NC)"; \
		fi; \
	fi

# Setup and configuration management
.PHONY: setup
setup: check-azure
	@echo "$(GREEN)Setting up tfwrapper configuration$(NC)"
	@echo ""
	@# Get Azure context
	$(eval SUBSCRIPTION_ID := $(shell az account show --query id -o tsv))
	$(eval TENANT_ID := $(shell az account show --query tenantId -o tsv))
	@echo "Azure context:"
	@echo "  Subscription: $(SUBSCRIPTION_ID)"
	@echo "  Tenant: $(TENANT_ID)"
	@echo ""
	@# Generate state.yml if needed
	@if [ ! -f conf/state.yml ]; then \
		echo "$(YELLOW)Generating conf/state.yml$(NC)"; \
		read -p "Resource Group for state [rg-tfstate-tfwrapper-001]: " rg; \
		rg=$${rg:-rg-tfstate-tfwrapper-001}; \
		read -p "Storage Account for state: " sa; \
		if [ -z "$$sa" ]; then echo "$(RED)Storage account is required$(NC)"; exit 1; fi; \
		sed -e "s/\$${SUBSCRIPTION_ID}/$(SUBSCRIPTION_ID)/" \
		    -e "s/\$${TENANT_ID}/$(TENANT_ID)/" \
		    -e "s/\$${RESOURCE_GROUP_NAME}/$$rg/" \
		    -e "s/\$${STORAGE_ACCOUNT_NAME}/$$sa/" \
		    conf/state.yml.template > conf/state.yml; \
		echo "$(GREEN)Created conf/state.yml$(NC)"; \
	else \
		echo "conf/state.yml already exists"; \
	fi
	@echo ""
	@echo "$(GREEN)Setup complete!$(NC)"
	@echo "You can now run: make <stack> <action> <env> <region>"

# Generate stack configuration
.PHONY: generate-stack-config
generate-stack-config: check-azure
	@if [ -z "$(STACK)" ] || [ -z "$(ENV)" ] || [ -z "$(REGION)" ]; then \
		echo "$(RED)Error: Missing parameters$(NC)"; \
		echo "Usage: make generate-stack-config STACK=<stack> ENV=<env> REGION=<region>"; \
		exit 1; \
	fi
	$(eval SUBSCRIPTION_ID := $(shell az account show --query id -o tsv))
	$(eval TENANT_ID := $(shell az account show --query tenantId -o tsv))
	$(eval FULL_REGION := $(call get_region,$(REGION)))
	@echo "$(YELLOW)Generating conf/$(ACCOUNT)_$(ENV)_$(FULL_REGION)_$(STACK).yml$(NC)"
	@sed -e "s/\$${SUBSCRIPTION_ID}/$(SUBSCRIPTION_ID)/" \
	     -e "s/\$${TENANT_ID}/$(TENANT_ID)/" \
	     -e "s/\$${REGION}/$(FULL_REGION)/" \
	     -e "s/\$${CLIENT_NAME}/$(CLIENT_NAME)/" \
	     -e "s/\$${ENVIRONMENT}/$(ENV)/" \
	     -e "s/\$${STACK}/$(STACK)/" \
	     conf/stack.yml.template > conf/$(ACCOUNT)_$(ENV)_$(FULL_REGION)_$(STACK).yml
	@echo "$(GREEN)Created stack configuration$(NC)"

# Check Azure CLI
.PHONY: check-azure
check-azure:
	@if ! command -v az &>/dev/null; then \
		echo "$(RED)Error: Azure CLI is not installed$(NC)"; \
		echo "Install with: brew install azure-cli"; \
		exit 1; \
	fi
	@if ! az account show --only-show-errors &>/dev/null; then \
		echo "$(RED)Error: Not logged in to Azure$(NC)"; \
		echo "Run: az login --use-device-code"; \
		exit 1; \
	fi

# Default target
.DEFAULT_GOAL := help

# Prevent errors from missing targets
.PHONY: help check-tfwrapper platform basic messaging charity-asb ps-sandbox bootstrap init plan apply destroy output refresh
