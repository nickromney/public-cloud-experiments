.DEFAULT_GOAL := help

# Use bash for shell commands (required for indirect variable expansion in check-env)
SHELL := /bin/bash

# Color output
GREEN := \033[0;32m
YELLOW := \033[1;33m
CYAN := \033[0;36m
NC := \033[0m # No Color

# Tools
TERRAGRUNT ?= terragrunt
TOFU := $(shell command -v tofu 2> /dev/null)
TERRAFORM := $(shell command -v terraform 2> /dev/null)
TFLINT := $(shell command -v tflint 2> /dev/null)
FMT_TOOL := $(if $(TOFU),tofu,$(if $(TERRAFORM),terraform,))
AZ ?= az

# Paths
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(ROOT_DIR)../..)
SCRIPTS_DIR ?= $(ROOT_DIR)deployment-scripts

# Stack name mappings (short-name -> directory)
# Format: <project>/<stack-alias>=<directory-path>
# Note: Using spaces to separate entries for filter to work correctly
STACK_MAP := subnet-calc/react-webapp=personal-sub/subnet-calc-react-webapp subnet-calc/react-webapp-easyauth=personal-sub/subnet-calc-react-webapp-easyauth subnet-calc/react-easyauth-e2e=personal-sub/subnet-calc-react-easyauth-e2e subnet-calc/react-apim=personal-sub/subnet-calc-react-webapp-apim subnet-calc/internal-apim=personal-sub/subnet-calc-internal-apim subnet-calc/static-web-apps=personal-sub/subnet-calc-static-web-apps subnet-calc/shared-components=personal-sub/subnet-calc-shared-components

# Function to resolve stack directory from project and stack alias
# Matches the exact key and extracts the value
get-stack-dir = $(strip $(patsubst $(1)/$(2)=%,%,$(filter $(1)/$(2)=%,$(STACK_MAP))))

# Configuration
RESOURCE_GROUP ?= rg-subnet-calc
PERSONAL_SUB_REGION ?= uksouth
AUTO_APPROVE ?= 0

# Terragrunt wrapper arguments
TG_ARGS ?=
VAR_FILE ?=
STAGE ?= 000
STAGE_DEFAULT := 000

# Valid verbs for argument parsing
VALID_VERBS := init plan apply destroy validate output deploy test show get clean unlock

# Shell function to find stage file
# Usage: $(call find_stage_file,STAGE,STACK_DIR)
define find_stage_file
	if [ -z "$(VAR_FILE)" ]; then \
		STAGE_FILE=$$(find $(2)/stages -maxdepth 1 -type f \( -name "$(1)-*.tfvars" -o -name "$(1)_*.tfvars" \) 2>/dev/null | head -n 1); \
		if [ -n "$$STAGE_FILE" ]; then \
			STAGE_BASENAME=$$(basename "$$STAGE_FILE"); \
			echo -e "$(CYAN)Using stage file: $$STAGE_BASENAME$(NC)"; \
			STAGE_VAR_FILE_ARG="-var-file=stages/$$STAGE_BASENAME"; \
		elif [ "$(1)" != "000" ]; then \
			echo -e "$(YELLOW)⚠️  Stage file not found: $(1)-*.tfvars or $(1)_*.tfvars$(NC)"; \
			echo -e "$(YELLOW)Available stages:$(NC)"; \
			ls $(2)/stages/*.tfvars 2>/dev/null | xargs -n1 basename || echo "  (none)"; \
			exit 1; \
		fi; \
	fi
endef

# VAR_FILE_ARG will be constructed dynamically based on STAGE and VAR_FILE
# Priority: VAR_FILE (explicit) > STAGE file (found) > none
VAR_FILE_ARG := $(if $(strip $(VAR_FILE)),-var-file="$(VAR_FILE)",)

# Resources with long provisioning/deletion times
SLOW_PROVISION_RESOURCES := apim aks appgw application-gateway
APIM_PROVISION_TIME := 37
APIM_DESTROY_TIME := 15
AKS_PROVISION_TIME := 10
AKS_DESTROY_TIME := 10
APPGW_PROVISION_TIME := 5
APPGW_DESTROY_TIME := 5

.PHONY: help

help:
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo -e "$(CYAN)  Terragrunt Multi-Stack Management$(NC)"
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Usage:$(NC)"
	@echo -e "  make <project> <stack> <verb> [component] [AUTO_APPROVE=1]"
	@echo -e ""
	@echo -e "$(YELLOW)Available Stacks:$(NC)"
	@echo -e "  subnet-calc shared-components       Shared Log Analytics Workspace + Key Vault"
	@echo -e "  subnet-calc react-webapp            Direct JWT authentication"
	@echo -e "  subnet-calc react-webapp-easyauth   Easy Auth with managed identity (no secrets)"
	@echo -e "  subnet-calc react-easyauth-e2e      Easy Auth E2E (frontend + backend, no JWT)"
	@echo -e "  subnet-calc react-apim              Public APIM with subscription keys"
	@echo -e "  subnet-calc internal-apim           Internal APIM with VNet integration"
	@echo -e "  subnet-calc static-web-apps         Import-only stack for existing SWAs"
	@echo -e ""
	@echo -e "$(YELLOW)Infrastructure Verbs:$(NC)"
	@echo -e "  init                          Initialize Terragrunt"
	@echo -e "  plan                          Show execution plan"
	@echo -e "  apply                         Apply infrastructure changes"
	@echo -e "  destroy                       Destroy all resources"
	@echo -e "  validate                      Validate Terraform configuration"
	@echo -e "  output                        Show Terragrunt outputs"
	@echo -e ""
	@echo -e "$(YELLOW)Deployment Verbs:$(NC)"
	@echo -e "  deploy function-app           Build and deploy Function App"
	@echo -e "  deploy frontend               Build and deploy React frontend"
	@echo -e "  deploy all                    Deploy both function and frontend"
	@echo -e ""
	@echo -e "$(YELLOW)Testing Verbs:$(NC)"
	@echo -e "  test apim                     Test API via APIM gateway"
	@echo -e "  test direct                   Test direct Function App access"
	@echo -e "  test endpoints                Test all endpoints"
	@echo -e "  test all                      Run all tests"
	@echo -e ""
	@echo -e "$(YELLOW)Utility Verbs:$(NC)"
	@echo -e "  show resources                Show deployed resource names/URLs"
	@echo -e "  get subscription-key          Display APIM subscription key"
	@echo -e "  clean                         Remove Terragrunt cache"
	@echo -e "  unlock <lock-id>              Force unlock Terraform state"
	@echo -e ""
	@echo -e "$(YELLOW)Examples:$(NC)"
	@echo -e "  make subnet-calc react-webapp-easyauth plan"
	@echo -e "  make subnet-calc react-webapp-easyauth apply"
	@echo -e "  make subnet-calc react-webapp-easyauth apply AUTO_APPROVE=1"
	@echo -e "  make subnet-calc react-webapp-easyauth deploy function-app"
	@echo -e "  make subnet-calc react-webapp-easyauth deploy frontend"
	@echo -e "  make subnet-calc react-easyauth-e2e apply AUTO_APPROVE=1"
	@echo -e "  make subnet-calc react-easyauth-e2e deploy all"
	@echo -e "  make subnet-calc react-apim plan"
	@echo -e "  make subnet-calc react-apim deploy all"
	@echo -e ""
	@echo -e "$(YELLOW)Staged Deployments:$(NC)"
	@echo -e "  make subnet-calc react-easyauth-e2e 100 plan            # Use stages/100-*.tfvars"
	@echo -e "  make subnet-calc react-easyauth-e2e 100 apply           # Apply stage 100"
	@echo -e "  make subnet-calc react-easyauth-e2e 200 apply AUTO_APPROVE=1"
	@echo -e "  make subnet-calc react-easyauth-e2e 400 plan            # Use stages/400-all.tfvars"
	@echo -e ""
	@echo -e "$(YELLOW)Advanced Options:$(NC)"
	@echo -e "  make subnet-calc react-apim plan VAR_FILE=stages/200-create-observability.tfvars"
	@echo -e "  make subnet-calc react-apim apply VAR_FILE=stages/300-byo-platform.tfvars TG_ARGS=--terragrunt-non-interactive AUTO_APPROVE=1"
	@echo -e ""
	@echo -e "$(YELLOW)Options:$(NC)"
	@echo -e "  AUTO_APPROVE=1                Skip confirmation prompts for apply/destroy"
	@echo -e "  VAR_FILE=path/to.tfvars       Pass an extra -var-file to plan/apply/destroy"
	@echo -e "  STAGE=<3-digit>               Use stages/<3-digit>-*.tfvars file (default: 000)"
	@echo -e "  TG_ARGS=\"--terragrunt-*\"     Extra Terragrunt CLI flags (applied to every command)"
	@echo -e ""
	@echo -e "$(YELLOW)Global Commands:$(NC)"
	@echo -e "  make check-env                Check required environment variables"
	@echo -e "  make setup                    Configure Azure backend"
	@echo -e "  make validate-all             Validate all stacks"
	@echo -e "  make clean-all                Clean all stack caches"
	@echo -e "  make fmt                      Format all Terraform files"
	@echo -e "  make lint                     Run tflint on all stacks"
	@echo -e "  make test                     Run Terraform tests (.tftest.hcl)"
	@echo -e "  make secure-app-plan          Plan secure-app/dev/uksouth stack"
	@echo -e "  make secure-app-apply         Apply secure-app/dev/uksouth stack"
	@echo -e "  make secure-app-destroy       Destroy secure-app/dev/uksouth stack"
	@echo -e ""
	@echo -e "$(YELLOW)Environment Variables (Required):$(NC)"
	@echo -e "  ARM_SUBSCRIPTION_ID           Azure subscription ID"
	@echo -e "  ARM_TENANT_ID                 Azure tenant ID"
	@echo -e "  TF_BACKEND_RG                 Backend resource group name"
	@echo -e "  TF_BACKEND_SA                 Backend storage account name"
	@echo -e "  TF_BACKEND_CONTAINER          Backend container name"
	@echo -e ""
	@echo -e "$(YELLOW)Environment Variables (Optional):$(NC)"
	@echo -e "  ARM_CLIENT_ID                 Service principal app ID (if not using az login)"
	@echo -e "  ARM_CLIENT_SECRET             Service principal secret (if not using az login)"
	@echo -e ""

# Check required environment variables
.PHONY: check-env
check-env:
	@missing_vars=""; \
	for var in ARM_SUBSCRIPTION_ID ARM_TENANT_ID TF_BACKEND_RG TF_BACKEND_SA TF_BACKEND_CONTAINER; do \
		if [ -z "$${!var}" ]; then \
			missing_vars="$$missing_vars $$var"; \
		fi; \
	done; \
	if [ -n "$$missing_vars" ]; then \
		echo -e "$(YELLOW)❌ Missing required environment variables:$$missing_vars$(NC)"; \
		echo -e ""; \
		echo -e "$(CYAN)Run the following to set up your environment:$(NC)"; \
		echo -e "  source ./setup-env.sh"; \
		echo -e ""; \
		echo -e "$(CYAN)Or export manually (Bash):$(NC)"; \
		echo -e "  export ARM_SUBSCRIPTION_ID=<your-subscription-id>"; \
		echo -e "  export ARM_TENANT_ID=<your-tenant-id>"; \
		echo -e "  export TF_BACKEND_RG=<backend-resource-group>"; \
		echo -e "  export TF_BACKEND_SA=<backend-storage-account>"; \
		echo -e "  export TF_BACKEND_CONTAINER=<backend-container-name>"; \
		echo -e ""; \
		echo -e "$(CYAN)Or in Nushell:$(NC)"; \
		echo -e "  \$$env.ARM_SUBSCRIPTION_ID = \"<your-subscription-id>\""; \
		echo -e "  \$$env.ARM_TENANT_ID = \"<your-tenant-id>\""; \
		echo -e "  \$$env.TF_BACKEND_RG = \"<backend-resource-group>\""; \
		echo -e "  \$$env.TF_BACKEND_SA = \"<backend-storage-account>\""; \
		echo -e "  \$$env.TF_BACKEND_CONTAINER = \"<backend-container-name>\""; \
		echo -e ""; \
		echo -e "$(YELLOW)Note:$(NC) This assumes you're using Azure CLI authentication (az login)."; \
		echo -e "If using service principal auth, also set ARM_CLIENT_ID and ARM_CLIENT_SECRET."; \
		echo -e ""; \
		exit 1; \
	fi

# Setup environment
.PHONY: setup
setup:
	@./setup-env.sh

# Global validation
.PHONY: validate-all
validate-all:
	@echo -e "$(YELLOW)Validating all stacks...$(NC)"
	@for dir in $$(find ps-az-sbx personal-sub -name "terragrunt.hcl" -exec dirname {} \;); do \
		echo -e "  → Validating $$dir"; \
		(cd $$dir && terragrunt init -upgrade && terragrunt validate) || exit 1; \
	done
	@echo -e "$(GREEN)✓ All configurations valid$(NC)"

# Global clean
.PHONY: clean-all
clean-all:
	@echo -e "$(YELLOW)Cleaning all stacks...$(NC)"
	@for dir in $$(find ps-az-sbx personal-sub -name "terragrunt.hcl" -exec dirname {} \;); do \
		echo -e "  → Cleaning $$dir"; \
		(cd $$dir && rm -rf .terraform .terragrunt-cache); \
	done
	@echo -e "$(GREEN)✓ All cleaned$(NC)"

# Global formatting
.PHONY: fmt format
fmt format:
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo -e "$(YELLOW)❌ Neither OpenTofu nor Terraform is installed$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)Formatting all Terraform files...$(NC)"
	@$(FMT_TOOL) fmt -recursive .
	@echo -e "$(GREEN)✓ Formatting complete$(NC)"

# Global linting
.PHONY: lint
lint:
	@if [ -z "$(TFLINT)" ]; then \
		echo -e "$(YELLOW)❌ tflint is not installed. Run: brew install tflint$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)Running tflint on all stacks...$(NC)"
	@failed=0; \
	for dir in modules/* personal-sub/subnet-calc-* cloudflare-publiccloudexperiments/*; do \
		if [ -d "$$dir" ] && [ -f "$$dir/main.tf" -o -f "$$dir/versions.tf" ]; then \
			echo -e "  → Linting $$dir"; \
			(cd $$dir && tflint --init > /dev/null 2>&1 && tflint) || failed=1; \
		fi; \
	done; \
	if [ $$failed -eq 0 ]; then \
		echo -e "$(GREEN)✓ All linting checks passed$(NC)"; \
	else \
		echo -e "$(YELLOW)❌ Some linting checks failed$(NC)"; \
		exit 1; \
	fi

# Global testing with Terraform test framework
.PHONY: test
test:
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo -e "$(YELLOW)❌ Neither OpenTofu nor Terraform is installed$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)Running Terraform tests on all stacks...$(NC)"
	@failed=0; \
	for dir in personal-sub/subnet-calc-* modules/*; do \
		if [ -d "$$dir" ] && ls $$dir/*.tftest.hcl > /dev/null 2>&1; then \
			echo -e "  → Testing $$dir"; \
			(cd $$dir && $(FMT_TOOL) init > /dev/null 2>&1 && $(FMT_TOOL) test) || failed=1; \
		fi; \
	done; \
	test_count=$$(find personal-sub/subnet-calc-* modules -name "*.tftest.hcl" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$test_count" -eq 0 ]; then \
		echo -e "$(YELLOW)⚠️  No .tftest.hcl files found$(NC)"; \
	elif [ $$failed -eq 0 ]; then \
		echo -e "$(GREEN)✓ All Terraform tests passed$(NC)"; \
	else \
		echo -e "$(YELLOW)❌ Some Terraform tests failed$(NC)"; \
		exit 1; \
	fi

# Parse multi-word commands
# This is where the magic happens - we route based on arguments
# Supports flexible argument ordering by detecting types:
#   - Verbs: init, plan, apply, destroy, validate, output, deploy, test, show, get, clean, unlock
#   - Stages: 3-digit numbers (000, 100, 200, etc.)
#   - Projects: subnet-calc
#   - Stacks: react-webapp, react-easyauth-e2e, etc.

# Smart argument parser - detects argument types regardless of position
# Receives: ARG1 ARG2 ARG3 ARG4 ARG5 as parameters
.PHONY: _parse-args
_parse-args:
	@PARSED_PROJECT=""; \
	PARSED_STACK=""; \
	PARSED_STAGE="$(STAGE_DEFAULT)"; \
	PARSED_VERB=""; \
	PARSED_COMPONENT=""; \
	for arg in "$(ARG1)" "$(ARG2)" "$(ARG3)" "$(ARG4)" "$(ARG5)"; do \
		if [ -z "$$arg" ]; then continue; fi; \
		if echo "$$arg" | grep -qE '^[0-9]{3}$$'; then \
			PARSED_STAGE=$$arg; \
		elif echo " $(VALID_VERBS) " | grep -q " $$arg "; then \
			if [ -z "$$PARSED_VERB" ]; then \
				PARSED_VERB=$$arg; \
			else \
				PARSED_COMPONENT=$$arg; \
			fi; \
		elif [ "$$arg" = "subnet-calc" ]; then \
			PARSED_PROJECT=$$arg; \
		elif [ -z "$$PARSED_STACK" ] && [ -n "$$PARSED_PROJECT" ]; then \
			PARSED_STACK=$$arg; \
		elif [ -z "$$PARSED_COMPONENT" ] && [ -n "$$PARSED_VERB" ]; then \
			PARSED_COMPONENT=$$arg; \
		fi; \
	done; \
	$(MAKE) --no-print-directory _route \
		PROJECT=$$PARSED_PROJECT \
		STACK=$$PARSED_STACK \
		STAGE=$$PARSED_STAGE \
		VERB=$$PARSED_VERB \
		COMPONENT=$$PARSED_COMPONENT

# Project-based routing (traditional: make subnet-calc <stack> [stage] <verb>)
subnet-calc:
	@$(MAKE) --no-print-directory _parse-args ARG1=subnet-calc ARG2=$(word 2,$(MAKECMDGOALS)) ARG3=$(word 3,$(MAKECMDGOALS)) ARG4=$(word 4,$(MAKECMDGOALS)) ARG5=$(word 5,$(MAKECMDGOALS))

# Verb-based routing (alternative: make <verb> [stage] subnet-calc <stack>)
# Note: 'test' is excluded as it conflicts with global test target
# These targets only execute if they are the FIRST word in MAKECMDGOALS to prevent double-execution
.PHONY: init plan apply destroy validate output deploy show get unlock
init plan apply destroy validate output:
	@if [ "$(firstword $(MAKECMDGOALS))" = "$@" ]; then \
		$(MAKE) --no-print-directory _parse-args ARG1=$(firstword $(MAKECMDGOALS)) ARG2=$(word 2,$(MAKECMDGOALS)) ARG3=$(word 3,$(MAKECMDGOALS)) ARG4=$(word 4,$(MAKECMDGOALS)) ARG5=$(word 5,$(MAKECMDGOALS)); \
	fi

deploy show get unlock:
	@if [ "$(firstword $(MAKECMDGOALS))" = "$@" ]; then \
		$(MAKE) --no-print-directory _parse-args ARG1=$(firstword $(MAKECMDGOALS)) ARG2=$(word 2,$(MAKECMDGOALS)) ARG3=$(word 3,$(MAKECMDGOALS)) ARG4=$(word 4,$(MAKECMDGOALS)) ARG5=$(word 5,$(MAKECMDGOALS)); \
	fi

# Internal routing target
.PHONY: _route
_route:
	@if [ -z "$(STACK)" ] || [ -z "$(VERB)" ]; then \
		echo -e "$(YELLOW)Usage: make $(PROJECT) <stack> <verb> [component]$(NC)"; \
		echo -e "Run 'make help' for details"; \
		exit 1; \
	fi
	@STACK_DIR=$$(echo '$(call get-stack-dir,$(PROJECT),$(STACK))'); \
	if [ -z "$$STACK_DIR" ]; then \
		echo -e "$(YELLOW)❌ Unknown stack: $(PROJECT)/$(STACK)$(NC)"; \
		echo -e "Available stacks:"; \
		echo -e "  subnet-calc/shared-components"; \
		echo -e "  subnet-calc/react-webapp"; \
		echo -e "  subnet-calc/react-webapp-easyauth"; \
		echo -e "  subnet-calc/react-easyauth-e2e"; \
		echo -e "  subnet-calc/react-apim"; \
		echo -e "  subnet-calc/internal-apim"; \
		echo -e "  subnet-calc/static-web-apps"; \
		exit 1; \
	fi; \
	echo -e "$(VALID_VERBS)" | grep -qw "$(VERB)" || { \
		echo -e "$(YELLOW)❌ Unknown verb: $(VERB)$(NC)"; \
		echo -e "Run 'make help' for available verbs"; \
		exit 1; \
	}; \
	$(MAKE) --no-print-directory _exec-$(VERB) STACK_DIR=$$STACK_DIR COMPONENT=$(COMPONENT)

# Infrastructure lifecycle verbs
.PHONY: _exec-init _exec-plan _exec-apply _exec-destroy _exec-validate _exec-output

_exec-init: check-env
	@echo -e "$(YELLOW)Initializing $(STACK_DIR)...$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) init -upgrade

_exec-plan: check-env
	@echo -e "$(YELLOW)Planning $(STACK_DIR)...$(NC)"
	@$(call find_stage_file,$(STAGE),$(STACK_DIR)); \
	[ -z "$(VAR_FILE)" ] || STAGE_VAR_FILE_ARG="$(VAR_FILE_ARG)"; \
	cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) init -upgrade && $(TERRAGRUNT) $(TG_ARGS) plan $$STAGE_VAR_FILE_ARG

_exec-apply: check-env
	@echo -e "$(YELLOW)Applying $(STACK_DIR)...$(NC)"
	@for resource in $(SLOW_PROVISION_RESOURCES); do \
		if echo "$(STACK_DIR)" | grep -q "$$resource"; then \
			case "$$resource" in \
				apim) echo -e "$(YELLOW)⏱️  Note: APIM provisioning takes ~$(APIM_PROVISION_TIME) minutes on first deployment$(NC)" ;; \
				aks) echo -e "$(YELLOW)⏱️  Note: AKS provisioning takes ~$(AKS_PROVISION_TIME) minutes$(NC)" ;; \
				appgw|application-gateway) echo -e "$(YELLOW)⏱️  Note: Application Gateway provisioning takes ~$(APPGW_PROVISION_TIME) minutes$(NC)" ;; \
			esac; \
			break; \
		fi; \
	done
	@STAGE_VAR_FILE_ARG=""; \
	$(call find_stage_file,$(STAGE),$(STACK_DIR)); \
	[ -z "$(VAR_FILE)" ] || STAGE_VAR_FILE_ARG="$(VAR_FILE_ARG)"; \
	if [ "$(AUTO_APPROVE)" = "1" ]; then \
		cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) init -upgrade && $(TERRAGRUNT) $(TG_ARGS) apply $$STAGE_VAR_FILE_ARG -auto-approve; \
	else \
		cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) init -upgrade && $(TERRAGRUNT) $(TG_ARGS) apply $$STAGE_VAR_FILE_ARG; \
	fi

_exec-destroy: check-env
	@echo -e "$(YELLOW)⚠️  WARNING: Destroying $(STACK_DIR)$(NC)"
	@for resource in $(SLOW_PROVISION_RESOURCES); do \
		if echo "$(STACK_DIR)" | grep -q "$$resource"; then \
			case "$$resource" in \
				apim) echo -e "$(YELLOW)⏱️  Note: APIM deletion takes ~$(APIM_DESTROY_TIME) minutes$(NC)" ;; \
				aks) echo -e "$(YELLOW)⏱️  Note: AKS deletion takes ~$(AKS_DESTROY_TIME) minutes$(NC)" ;; \
				appgw|application-gateway) echo -e "$(YELLOW)⏱️  Note: Application Gateway deletion takes ~$(APPGW_DESTROY_TIME) minutes$(NC)" ;; \
			esac; \
			break; \
		fi; \
	done
	@STAGE_VAR_FILE_ARG=""; \
	$(call find_stage_file,$(STAGE),$(STACK_DIR)); \
	[ -z "$(VAR_FILE)" ] || STAGE_VAR_FILE_ARG="$(VAR_FILE_ARG)"; \
	cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) destroy $$STAGE_VAR_FILE_ARG

_exec-validate: check-env
	@echo -e "$(YELLOW)Validating $(STACK_DIR)...$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) validate

_exec-output: check-env
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) $(TG_ARGS) output

# Deployment verbs
.PHONY: _exec-deploy

_exec-deploy:
	@if [ "$(COMPONENT)" = "function-app" ]; then \
		$(MAKE) --no-print-directory _deploy-function STACK_DIR=$(STACK_DIR); \
	elif [ "$(COMPONENT)" = "frontend" ]; then \
		$(MAKE) --no-print-directory _deploy-frontend STACK_DIR=$(STACK_DIR); \
	elif [ "$(COMPONENT)" = "all" ]; then \
		$(MAKE) --no-print-directory _deploy-function STACK_DIR=$(STACK_DIR); \
		$(MAKE) --no-print-directory _deploy-frontend STACK_DIR=$(STACK_DIR); \
	else \
		echo -e "$(YELLOW)Usage: make $(PROJECT) $(STACK) deploy <function-app|frontend|all>$(NC)"; \
		exit 1; \
	fi

.PHONY: _deploy-function
_deploy-function: check-env
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo -e "$(CYAN)  Deploying Function App$(NC)"
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@FUNCTION_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw function_app_name 2>/dev/null); \
	if [ -z "$$FUNCTION_APP_NAME" ]; then \
		echo -e "$(YELLOW)❌ FUNCTION_APP_NAME not found. Run 'make $(PROJECT) $(STACK) apply' first.$(NC)"; \
		exit 1; \
	fi && \
	echo -e "Function App: $$FUNCTION_APP_NAME" && \
	$(SCRIPTS_DIR)/build-function-zip.sh $(ROOT_DIR)function-app.zip && \
	$(AZ) functionapp deployment source config-zip \
		--resource-group $(RESOURCE_GROUP) \
		--name $$FUNCTION_APP_NAME \
		--src $(ROOT_DIR)function-app.zip \
		--build-remote true \
		--timeout 600 && \
	rm -f $(ROOT_DIR)function-app.zip && \
	echo -e "$(GREEN)✅ Function App deployed successfully$(NC)"

.PHONY: _deploy-frontend
_deploy-frontend: check-env
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo -e "$(CYAN)  Deploying React Frontend$(NC)"
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@WEB_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw web_app_name 2>/dev/null); \
	API_BASE_URL=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_api_url 2>/dev/null || $(TERRAGRUNT) output -raw function_app_api_base_url 2>/dev/null); \
	if [ -z "$$WEB_APP_NAME" ] || [ -z "$$API_BASE_URL" ]; then \
		echo -e "$(YELLOW)❌ WEB_APP_NAME or API_BASE_URL not found. Run 'make $(PROJECT) $(STACK) apply' first.$(NC)"; \
		exit 1; \
	fi && \
	echo -e "Web App: $$WEB_APP_NAME" && \
	echo -e "API URL: $$API_BASE_URL" && \
	if echo "$(STACK)" | grep -q "easyauth"; then \
		echo -e "$(CYAN)Using Easy Auth build script...$(NC)"; \
		API_BASE_URL=$$API_BASE_URL $(SCRIPTS_DIR)/build-easyauth-frontend-zip.sh $(ROOT_DIR)react-app.zip; \
	else \
		echo -e "$(CYAN)Using JWT auth build script...$(NC)"; \
		API_BASE_URL=$$API_BASE_URL $(SCRIPTS_DIR)/build-deployment-zip.sh $(ROOT_DIR)react-app.zip; \
	fi && \
	$(AZ) webapp deploy \
		--resource-group $(RESOURCE_GROUP) \
		--name $$WEB_APP_NAME \
		--src-path $(ROOT_DIR)react-app.zip \
		--type zip && \
	rm -f $(ROOT_DIR)react-app.zip && \
	echo -e "$(GREEN)✅ Frontend deployed successfully$(NC)" && \
	echo -e "$(GREEN)🌐 Web App URL: https://$$WEB_APP_NAME.azurewebsites.net$(NC)"

# Testing verbs
.PHONY: _exec-test

_exec-test:
	@if [ "$(COMPONENT)" = "apim" ]; then \
		$(MAKE) --no-print-directory _test-apim STACK_DIR=$(STACK_DIR); \
	elif [ "$(COMPONENT)" = "direct" ]; then \
		$(MAKE) --no-print-directory _test-direct STACK_DIR=$(STACK_DIR); \
	elif [ "$(COMPONENT)" = "endpoints" ]; then \
		$(MAKE) --no-print-directory _test-endpoints STACK_DIR=$(STACK_DIR); \
	elif [ "$(COMPONENT)" = "all" ]; then \
		$(MAKE) --no-print-directory _test-apim STACK_DIR=$(STACK_DIR) || true; \
		$(MAKE) --no-print-directory _test-direct STACK_DIR=$(STACK_DIR) || true; \
		$(MAKE) --no-print-directory _test-endpoints STACK_DIR=$(STACK_DIR) || true; \
	else \
		echo -e "$(YELLOW)Usage: make $(PROJECT) $(STACK) test <apim|direct|endpoints|all>$(NC)"; \
		exit 1; \
	fi

.PHONY: _test-apim
_test-apim:
	@echo -e "$(YELLOW)Testing API via APIM gateway...$(NC)"
	@APIM_API_URL=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_api_url 2>/dev/null); \
	APIM_SUBSCRIPTION_KEY=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_subscription_key 2>/dev/null); \
	if [ -z "$$APIM_API_URL" ]; then \
		echo -e "$(YELLOW)⚠️  This stack does not have APIM configured$(NC)"; \
		exit 0; \
	fi; \
	echo -e "URL: $$APIM_API_URL/api/v1/health"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $$APIM_SUBSCRIPTION_KEY" "$$APIM_API_URL/api/v1/health"); \
	if [ "$$status" -eq 200 ]; then \
		echo -e "$(GREEN)✅ APIM Gateway: Status $$status (working)$(NC)"; \
	else \
		echo -e "$(YELLOW)❌ APIM Gateway unreachable (Status: $$status)$(NC)"; \
		exit 1; \
	fi

.PHONY: _test-direct
_test-direct:
	@echo -e "$(YELLOW)Testing direct Function App access...$(NC)"
	@FUNCTION_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw function_app_name 2>/dev/null); \
	if [ -z "$$FUNCTION_APP_NAME" ]; then \
		echo -e "$(YELLOW)❌ Function App not found$(NC)"; \
		exit 1; \
	fi; \
	echo -e "URL: https://$$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"); \
	if [ "$$status" -eq 403 ]; then \
		echo -e "$(GREEN)✅ Direct access blocked (Status $$status) - IP restrictions working!$(NC)"; \
	elif [ "$$status" -eq 200 ]; then \
		echo -e "$(YELLOW)⚠️  Direct access allowed (Status $$status) - IP restrictions NOT enforced$(NC)"; \
	else \
		echo -e "$(YELLOW)Status: $$status$(NC)"; \
	fi

.PHONY: _test-endpoints
_test-endpoints:
	@$(MAKE) --no-print-directory _test-apim STACK_DIR=$(STACK_DIR) || true
	@$(MAKE) --no-print-directory _test-direct STACK_DIR=$(STACK_DIR) || true
	@echo -e "$(YELLOW)Testing Web App...$(NC)"
	@WEB_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw web_app_name 2>/dev/null); \
	if [ -z "$$WEB_APP_NAME" ]; then \
		echo -e "$(YELLOW)❌ Web App not found$(NC)"; \
		exit 1; \
	fi; \
	echo -e "URL: https://$$WEB_APP_NAME.azurewebsites.net"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$$WEB_APP_NAME.azurewebsites.net"); \
	if [ "$$status" -eq 200 ]; then \
		echo -e "$(GREEN)✅ Web App: Status $$status (working)$(NC)"; \
	else \
		echo -e "$(YELLOW)❌ Web App unreachable (Status: $$status)$(NC)"; \
	fi

# Secure App convenience verbs
.PHONY: secure-app-init secure-app-plan secure-app-apply secure-app-destroy secure-app-output secure-app-clean

secure-app-init: check-env
	@cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) init -upgrade

secure-app-plan: check-env
	@cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) init -upgrade && $(TERRAGRUNT) plan

secure-app-apply: check-env
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) init -upgrade && $(TERRAGRUNT) apply -auto-approve; \
	else \
		cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) init -upgrade && $(TERRAGRUNT) apply; \
	fi

secure-app-destroy: check-env
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) destroy -auto-approve; \
	else \
		cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) destroy; \
	fi

secure-app-output: check-env
	@cd workloads/secure-app/envs/dev/uksouth && $(TERRAGRUNT) output

secure-app-clean:
	@cd workloads/secure-app/envs/dev/uksouth && rm -rf .terraform .terragrunt-cache
	@echo -e "$(GREEN)✓ Cleaned secure-app/dev/uksouth$(NC)"

# Utility verbs
.PHONY: _exec-show _exec-get _exec-clean _exec-unlock

_exec-show:
	@if [ "$(COMPONENT)" = "resources" ]; then \
		$(MAKE) --no-print-directory _show-resources STACK_DIR=$(STACK_DIR); \
	else \
		echo -e "$(YELLOW)Usage: make $(PROJECT) $(STACK) show resources$(NC)"; \
		exit 1; \
	fi

.PHONY: _show-resources
_show-resources: check-env
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo -e "$(CYAN)  Deployed Resources$(NC)"
	@echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output deployment_summary 2>/dev/null || $(TERRAGRUNT) output

_exec-get:
	@if [ "$(COMPONENT)" = "subscription-key" ]; then \
		$(MAKE) --no-print-directory _get-subscription-key STACK_DIR=$(STACK_DIR); \
	else \
		echo -e "$(YELLOW)Usage: make $(PROJECT) $(STACK) get subscription-key$(NC)"; \
		exit 1; \
	fi

.PHONY: _get-subscription-key
_get-subscription-key: check-env
	@APIM_SUBSCRIPTION_KEY=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_subscription_key 2>/dev/null); \
	if [ -z "$$APIM_SUBSCRIPTION_KEY" ]; then \
		echo -e "$(YELLOW)❌ APIM subscription key not found (stack may not have APIM)$(NC)"; \
		exit 1; \
	fi; \
	echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"; \
	echo -e "$(CYAN)  APIM Subscription Key$(NC)"; \
	echo -e "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"; \
	echo -e "Primary Key: $$APIM_SUBSCRIPTION_KEY"

_exec-clean:
	@echo -e "$(YELLOW)Cleaning $(STACK_DIR) cache...$(NC)"
	@cd $(STACK_DIR) && rm -rf .terraform .terragrunt-cache
	@echo -e "$(GREEN)✓ Cleaned $(STACK_DIR)$(NC)"

_exec-unlock: check-env
	@if [ -z "$(COMPONENT)" ]; then \
		echo -e "$(YELLOW)❌ Lock ID required$(NC)"; \
		echo -e "Usage: make $(PROJECT) $(STACK) unlock <lock-id>"; \
		echo -e "Example: make subnet-calc react-apim unlock abc123-def456-ghi789"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)Force unlocking state with ID: $(COMPONENT)$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) force-unlock -force $(COMPONENT)

# Suppress "Nothing to be done" messages for command arguments
%:
	@:
