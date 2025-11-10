.DEFAULT_GOAL := help

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
STACK_MAP := subnet-calc/react-webapp=personal-sub/subnet-calc-react-webapp subnet-calc/react-apim=personal-sub/subnet-calc-react-webapp-apim subnet-calc/internal-apim=personal-sub/subnet-calc-internal-apim subnet-calc/static-web-apps=personal-sub/subnet-calc-static-web-apps subnet-calc/shared-components=personal-sub/subnet-calc-shared-components

# Function to resolve stack directory from project and stack alias
# Matches the exact key and extracts the value
get-stack-dir = $(strip $(patsubst $(1)/$(2)=%,%,$(filter $(1)/$(2)=%,$(STACK_MAP))))

# Configuration
RESOURCE_GROUP ?= rg-subnet-calc
PERSONAL_SUB_REGION ?= uksouth

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
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(CYAN)  Terragrunt Multi-Stack Management$(NC)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  make <project> <stack> <verb> [component]"
	@echo ""
	@echo "$(YELLOW)Available Stacks:$(NC)"
	@echo "  subnet-calc react-webapp      Direct JWT authentication"
	@echo "  subnet-calc react-apim        Public APIM with subscription keys"
	@echo "  subnet-calc internal-apim     Internal APIM with VNet integration"
	@echo ""
	@echo "$(YELLOW)Infrastructure Verbs:$(NC)"
	@echo "  init                          Initialize Terragrunt"
	@echo "  plan                          Show execution plan"
	@echo "  apply                         Apply infrastructure changes"
	@echo "  destroy                       Destroy all resources"
	@echo "  validate                      Validate Terraform configuration"
	@echo "  output                        Show Terragrunt outputs"
	@echo ""
	@echo "$(YELLOW)Deployment Verbs:$(NC)"
	@echo "  deploy function-app           Build and deploy Function App"
	@echo "  deploy frontend               Build and deploy React frontend"
	@echo "  deploy all                    Deploy both function and frontend"
	@echo ""
	@echo "$(YELLOW)Testing Verbs:$(NC)"
	@echo "  test apim                     Test API via APIM gateway"
	@echo "  test direct                   Test direct Function App access"
	@echo "  test endpoints                Test all endpoints"
	@echo "  test all                      Run all tests"
	@echo ""
	@echo "$(YELLOW)Utility Verbs:$(NC)"
	@echo "  show resources                Show deployed resource names/URLs"
	@echo "  get subscription-key          Display APIM subscription key"
	@echo "  clean                         Remove Terragrunt cache"
	@echo "  unlock <lock-id>              Force unlock Terraform state"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make subnet-calc react-apim init"
	@echo "  make subnet-calc react-apim plan"
	@echo "  make subnet-calc react-apim deploy function-app"
	@echo "  make subnet-calc react-apim deploy frontend"
	@echo "  make subnet-calc react-apim test apim"
	@echo "  make subnet-calc internal-apim init"
	@echo ""
	@echo "$(YELLOW)Global Commands:$(NC)"
	@echo "  make setup                    Configure Azure backend"
	@echo "  make validate-all             Validate all stacks"
	@echo "  make clean-all                Clean all stack caches"
	@echo "  make fmt                      Format all Terraform files"
	@echo "  make lint                     Run tflint on all stacks"
	@echo "  make test                     Run Terraform tests (.tftest.hcl)"
	@echo ""

# Setup environment
.PHONY: setup
setup:
	@./setup-env.sh

# Global validation
.PHONY: validate-all
validate-all:
	@echo "$(YELLOW)Validating all stacks...$(NC)"
	@for dir in $$(find ps-az-sbx personal-sub -name "terragrunt.hcl" -exec dirname {} \;); do \
		echo "  → Validating $$dir"; \
		(cd $$dir && terragrunt init -upgrade && terragrunt validate) || exit 1; \
	done
	@echo "$(GREEN)✓ All configurations valid$(NC)"

# Global clean
.PHONY: clean-all
clean-all:
	@echo "$(YELLOW)Cleaning all stacks...$(NC)"
	@for dir in $$(find ps-az-sbx personal-sub -name "terragrunt.hcl" -exec dirname {} \;); do \
		echo "  → Cleaning $$dir"; \
		(cd $$dir && rm -rf .terraform .terragrunt-cache); \
	done
	@echo "$(GREEN)✓ All cleaned$(NC)"

# Global formatting
.PHONY: fmt format
fmt format:
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo "$(YELLOW)❌ Neither OpenTofu nor Terraform is installed$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Formatting all Terraform files...$(NC)"
	@$(FMT_TOOL) fmt -recursive .
	@echo "$(GREEN)✓ Formatting complete$(NC)"

# Global linting
.PHONY: lint
lint:
	@if [ -z "$(TFLINT)" ]; then \
		echo "$(YELLOW)❌ tflint is not installed. Run: brew install tflint$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Running tflint on all stacks...$(NC)"
	@failed=0; \
	for dir in modules/* personal-sub/subnet-calc-* cloudflare-publiccloudexperiments/*; do \
		if [ -d "$$dir" ] && [ -f "$$dir/main.tf" -o -f "$$dir/versions.tf" ]; then \
			echo "  → Linting $$dir"; \
			(cd $$dir && tflint --init > /dev/null 2>&1 && tflint) || failed=1; \
		fi; \
	done; \
	if [ $$failed -eq 0 ]; then \
		echo "$(GREEN)✓ All linting checks passed$(NC)"; \
	else \
		echo "$(YELLOW)❌ Some linting checks failed$(NC)"; \
		exit 1; \
	fi

# Global testing with Terraform test framework
.PHONY: test
test:
	@if [ -z "$(FMT_TOOL)" ]; then \
		echo "$(YELLOW)❌ Neither OpenTofu nor Terraform is installed$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Running Terraform tests on all stacks...$(NC)"
	@failed=0; \
	for dir in personal-sub/subnet-calc-* modules/*; do \
		if [ -d "$$dir" ] && ls $$dir/*.tftest.hcl > /dev/null 2>&1; then \
			echo "  → Testing $$dir"; \
			(cd $$dir && $(FMT_TOOL) test) || failed=1; \
		fi; \
	done; \
	test_count=$$(find personal-sub/subnet-calc-* modules -name "*.tftest.hcl" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$test_count" -eq 0 ]; then \
		echo "$(YELLOW)⚠️  No .tftest.hcl files found$(NC)"; \
	elif [ $$failed -eq 0 ]; then \
		echo "$(GREEN)✓ All Terraform tests passed$(NC)"; \
	else \
		echo "$(YELLOW)❌ Some Terraform tests failed$(NC)"; \
		exit 1; \
	fi

# Parse multi-word commands
# This is where the magic happens - we route based on arguments

# Infrastructure lifecycle commands
subnet-calc:
	@$(MAKE) --no-print-directory _route PROJECT=subnet-calc STACK=$(word 2,$(MAKECMDGOALS)) VERB=$(word 3,$(MAKECMDGOALS)) COMPONENT=$(word 4,$(MAKECMDGOALS))

# Internal routing target
.PHONY: _route
_route:
	@if [ -z "$(STACK)" ] || [ -z "$(VERB)" ]; then \
		echo "$(YELLOW)Usage: make $(PROJECT) <stack> <verb> [component]$(NC)"; \
		echo "Run 'make help' for details"; \
		exit 1; \
	fi
	@STACK_DIR=$$(echo '$(call get-stack-dir,$(PROJECT),$(STACK))'); \
	if [ -z "$$STACK_DIR" ]; then \
		echo "$(YELLOW)❌ Unknown stack: $(PROJECT)/$(STACK)$(NC)"; \
		echo "Available stacks:"; \
		echo "  subnet-calc/react-webapp"; \
		echo "  subnet-calc/react-apim"; \
		echo "  subnet-calc/internal-apim"; \
		exit 1; \
	fi; \
	VALID_VERBS="init plan apply destroy validate output deploy test show get clean unlock"; \
	echo "$$VALID_VERBS" | grep -qw "$(VERB)" || { \
		echo "$(YELLOW)❌ Unknown verb: $(VERB)$(NC)"; \
		echo "Run 'make help' for available verbs"; \
		exit 1; \
	}; \
	$(MAKE) --no-print-directory _exec-$(VERB) STACK_DIR=$$STACK_DIR COMPONENT=$(COMPONENT)

# Infrastructure lifecycle verbs
.PHONY: _exec-init _exec-plan _exec-apply _exec-destroy _exec-validate _exec-output

_exec-init:
	@echo "$(YELLOW)Initializing $(STACK_DIR)...$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) init -upgrade

_exec-plan:
	@echo "$(YELLOW)Planning $(STACK_DIR)...$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) init -upgrade && $(TERRAGRUNT) plan

_exec-apply:
	@echo "$(YELLOW)Applying $(STACK_DIR)...$(NC)"
	@for resource in $(SLOW_PROVISION_RESOURCES); do \
		if echo "$(STACK_DIR)" | grep -q "$$resource"; then \
			case "$$resource" in \
				apim) echo "$(YELLOW)⏱️  Note: APIM provisioning takes ~$(APIM_PROVISION_TIME) minutes on first deployment$(NC)" ;; \
				aks) echo "$(YELLOW)⏱️  Note: AKS provisioning takes ~$(AKS_PROVISION_TIME) minutes$(NC)" ;; \
				appgw|application-gateway) echo "$(YELLOW)⏱️  Note: Application Gateway provisioning takes ~$(APPGW_PROVISION_TIME) minutes$(NC)" ;; \
			esac; \
			break; \
		fi; \
	done
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) init -upgrade && $(TERRAGRUNT) apply

_exec-destroy:
	@echo "$(YELLOW)⚠️  WARNING: Destroying $(STACK_DIR)$(NC)"
	@for resource in $(SLOW_PROVISION_RESOURCES); do \
		if echo "$(STACK_DIR)" | grep -q "$$resource"; then \
			case "$$resource" in \
				apim) echo "$(YELLOW)⏱️  Note: APIM deletion takes ~$(APIM_DESTROY_TIME) minutes$(NC)" ;; \
				aks) echo "$(YELLOW)⏱️  Note: AKS deletion takes ~$(AKS_DESTROY_TIME) minutes$(NC)" ;; \
				appgw|application-gateway) echo "$(YELLOW)⏱️  Note: Application Gateway deletion takes ~$(APPGW_DESTROY_TIME) minutes$(NC)" ;; \
			esac; \
			break; \
		fi; \
	done
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) destroy

_exec-validate:
	@echo "$(YELLOW)Validating $(STACK_DIR)...$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) validate

_exec-output:
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output

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
		echo "$(YELLOW)Usage: make $(PROJECT) $(STACK) deploy <function-app|frontend|all>$(NC)"; \
		exit 1; \
	fi

.PHONY: _deploy-function
_deploy-function:
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(CYAN)  Deploying Function App$(NC)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@FUNCTION_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw function_app_name 2>/dev/null); \
	if [ -z "$$FUNCTION_APP_NAME" ]; then \
		echo "$(YELLOW)❌ FUNCTION_APP_NAME not found. Run 'make $(PROJECT) $(STACK) apply' first.$(NC)"; \
		exit 1; \
	fi && \
	echo "Function App: $$FUNCTION_APP_NAME" && \
	$(SCRIPTS_DIR)/build-function-zip.sh $(ROOT_DIR)/function-app.zip && \
	$(AZ) functionapp deployment source config-zip \
		--resource-group $(RESOURCE_GROUP) \
		--name $$FUNCTION_APP_NAME \
		--src $(ROOT_DIR)/function-app.zip \
		--build-remote true \
		--timeout 600 && \
	rm -f $(ROOT_DIR)/function-app.zip && \
	echo "$(GREEN)✅ Function App deployed successfully$(NC)"

.PHONY: _deploy-frontend
_deploy-frontend:
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(CYAN)  Deploying React Frontend$(NC)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@WEB_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw web_app_name 2>/dev/null); \
	API_BASE_URL=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_api_url 2>/dev/null || $(TERRAGRUNT) output -raw function_app_api_base_url 2>/dev/null); \
	if [ -z "$$WEB_APP_NAME" ] || [ -z "$$API_BASE_URL" ]; then \
		echo "$(YELLOW)❌ WEB_APP_NAME or API_BASE_URL not found. Run 'make $(PROJECT) $(STACK) apply' first.$(NC)"; \
		exit 1; \
	fi && \
	echo "Web App: $$WEB_APP_NAME" && \
	echo "API URL: $$API_BASE_URL" && \
	API_BASE_URL=$$API_BASE_URL $(SCRIPTS_DIR)/build-deployment-zip.sh $(ROOT_DIR)/react-app.zip && \
	$(AZ) webapp deploy \
		--resource-group $(RESOURCE_GROUP) \
		--name $$WEB_APP_NAME \
		--src-path $(ROOT_DIR)/react-app.zip \
		--type zip && \
	rm -f $(ROOT_DIR)/react-app.zip && \
	echo "$(GREEN)✅ Frontend deployed successfully$(NC)" && \
	echo "$(GREEN)🌐 Web App URL: https://$$WEB_APP_NAME.azurewebsites.net$(NC)"

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
		echo "$(YELLOW)Usage: make $(PROJECT) $(STACK) test <apim|direct|endpoints|all>$(NC)"; \
		exit 1; \
	fi

.PHONY: _test-apim
_test-apim:
	@echo "$(YELLOW)Testing API via APIM gateway...$(NC)"
	@APIM_API_URL=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_api_url 2>/dev/null); \
	APIM_SUBSCRIPTION_KEY=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_subscription_key 2>/dev/null); \
	if [ -z "$$APIM_API_URL" ]; then \
		echo "$(YELLOW)⚠️  This stack does not have APIM configured$(NC)"; \
		exit 0; \
	fi; \
	echo "URL: $$APIM_API_URL/api/v1/health"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $$APIM_SUBSCRIPTION_KEY" "$$APIM_API_URL/api/v1/health"); \
	if [ "$$status" -eq 200 ]; then \
		echo "$(GREEN)✅ APIM Gateway: Status $$status (working)$(NC)"; \
	else \
		echo "$(YELLOW)❌ APIM Gateway unreachable (Status: $$status)$(NC)"; \
		exit 1; \
	fi

.PHONY: _test-direct
_test-direct:
	@echo "$(YELLOW)Testing direct Function App access...$(NC)"
	@FUNCTION_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw function_app_name 2>/dev/null); \
	if [ -z "$$FUNCTION_APP_NAME" ]; then \
		echo "$(YELLOW)❌ Function App not found$(NC)"; \
		exit 1; \
	fi; \
	echo "URL: https://$$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$$FUNCTION_APP_NAME.azurewebsites.net/api/v1/health"); \
	if [ "$$status" -eq 403 ]; then \
		echo "$(GREEN)✅ Direct access blocked (Status $$status) - IP restrictions working!$(NC)"; \
	elif [ "$$status" -eq 200 ]; then \
		echo "$(YELLOW)⚠️  Direct access allowed (Status $$status) - IP restrictions NOT enforced$(NC)"; \
	else \
		echo "$(YELLOW)Status: $$status$(NC)"; \
	fi

.PHONY: _test-endpoints
_test-endpoints:
	@$(MAKE) --no-print-directory _test-apim STACK_DIR=$(STACK_DIR) || true
	@$(MAKE) --no-print-directory _test-direct STACK_DIR=$(STACK_DIR) || true
	@echo "$(YELLOW)Testing Web App...$(NC)"
	@WEB_APP_NAME=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw web_app_name 2>/dev/null); \
	if [ -z "$$WEB_APP_NAME" ]; then \
		echo "$(YELLOW)❌ Web App not found$(NC)"; \
		exit 1; \
	fi; \
	echo "URL: https://$$WEB_APP_NAME.azurewebsites.net"; \
	status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$$WEB_APP_NAME.azurewebsites.net"); \
	if [ "$$status" -eq 200 ]; then \
		echo "$(GREEN)✅ Web App: Status $$status (working)$(NC)"; \
	else \
		echo "$(YELLOW)❌ Web App unreachable (Status: $$status)$(NC)"; \
	fi

# Utility verbs
.PHONY: _exec-show _exec-get _exec-clean _exec-unlock

_exec-show:
	@if [ "$(COMPONENT)" = "resources" ]; then \
		$(MAKE) --no-print-directory _show-resources STACK_DIR=$(STACK_DIR); \
	else \
		echo "$(YELLOW)Usage: make $(PROJECT) $(STACK) show resources$(NC)"; \
		exit 1; \
	fi

.PHONY: _show-resources
_show-resources:
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(CYAN)  Deployed Resources$(NC)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output deployment_summary 2>/dev/null || $(TERRAGRUNT) output

_exec-get:
	@if [ "$(COMPONENT)" = "subscription-key" ]; then \
		$(MAKE) --no-print-directory _get-subscription-key STACK_DIR=$(STACK_DIR); \
	else \
		echo "$(YELLOW)Usage: make $(PROJECT) $(STACK) get subscription-key$(NC)"; \
		exit 1; \
	fi

.PHONY: _get-subscription-key
_get-subscription-key:
	@APIM_SUBSCRIPTION_KEY=$$(cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw apim_subscription_key 2>/dev/null); \
	if [ -z "$$APIM_SUBSCRIPTION_KEY" ]; then \
		echo "$(YELLOW)❌ APIM subscription key not found (stack may not have APIM)$(NC)"; \
		exit 1; \
	fi; \
	echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"; \
	echo "$(CYAN)  APIM Subscription Key$(NC)"; \
	echo "$(CYAN)═══════════════════════════════════════════════════════════════$(NC)"; \
	echo "Primary Key: $$APIM_SUBSCRIPTION_KEY"

_exec-clean:
	@echo "$(YELLOW)Cleaning $(STACK_DIR) cache...$(NC)"
	@cd $(STACK_DIR) && rm -rf .terraform .terragrunt-cache
	@echo "$(GREEN)✓ Cleaned $(STACK_DIR)$(NC)"

_exec-unlock:
	@if [ -z "$(COMPONENT)" ]; then \
		echo "$(YELLOW)❌ Lock ID required$(NC)"; \
		echo "Usage: make $(PROJECT) $(STACK) unlock <lock-id>"; \
		echo "Example: make subnet-calc react-apim unlock abc123-def456-ghi789"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Force unlocking state with ID: $(COMPONENT)$(NC)"
	@cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) force-unlock -force $(COMPONENT)

# Suppress "Nothing to be done" messages for command arguments
%:
	@:
