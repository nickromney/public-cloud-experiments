.DEFAULT_GOAL := help

# Paths
STACK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)../../../..)
SCRIPTS_DIR := $(abspath $(STACK_DIR)../../deployment-scripts)
FRONTEND_REACT_DIR := $(REPO_ROOT)/subnet-calculator/frontend-react
API_FUNCTION_DIR := $(REPO_ROOT)/subnet-calculator/api-fastapi-azure-function

# Tools
TERRAGRUNT ?= terragrunt
AZ ?= az

# Configuration
RESOURCE_GROUP := rg-subnet-calc
PERSONAL_SUB_REGION ?= uksouth

# Terragrunt output helpers
define tg-output
$(shell cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw $(1) 2>/dev/null)
endef

WEB_APP_NAME := $(call tg-output,web_app_name)
FUNCTION_APP_NAME := $(call tg-output,function_app_name)
APIM_GATEWAY_URL := $(call tg-output,apim_gateway_url)
APIM_API_URL := $(call tg-output,apim_api_url)
APIM_NAME := $(call tg-output,apim_name)
APIM_SUBSCRIPTION_KEY := $(call tg-output,apim_subscription_key)

.PHONY: help check-env init plan apply destroy reconfigure validate
.PHONY: deploy-function deploy-frontend deploy-all clean-cache
.PHONY: show-resources test-endpoints test-apim unlock

help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Subnet Calculator React Web App with APIM - Terragrunt Stack"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "Infrastructure Management:"
	@echo "  make check-env        - Verify environment variables are set"
	@echo "  make init             - Initialize Terragrunt"
	@echo "  make plan             - Show execution plan"
	@echo "  make apply            - Apply infrastructure changes"
	@echo "  make destroy          - Destroy all resources"
	@echo "  make validate         - Validate Terraform configuration"
	@echo "  make reconfigure      - Clean cache and reinitialize"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-function  - Build and deploy Function App backend (AUTH_METHOD=none)"
	@echo "  make deploy-frontend  - Build and deploy React frontend (via APIM)"
	@echo "  make deploy-all       - Deploy both function and frontend"
	@echo ""
	@echo "Testing & Validation:"
	@echo "  make show-resources   - Show deployed resource names and URLs"
	@echo "  make test-apim        - Test API via APIM gateway (with subscription key)"
	@echo "  make test-direct      - Test Function App direct access (should fail if enforced)"
	@echo "  make test-endpoints   - Test both APIM and web app endpoints"
	@echo ""
	@echo "Utilities:"
	@echo "  make get-subscription-key - Display APIM subscription key"
	@echo "  make clean-cache      - Remove Terragrunt cache"
	@echo "  make unlock LOCK_ID=<id> - Force unlock Terraform state"
	@echo ""
	@echo "Environment Variables:"
	@echo "  PERSONAL_SUB_REGION   - Azure region (default: uksouth)"
	@echo "  RESOURCE_GROUP        - Resource group name"
	@echo ""
	@echo "APIM Architecture:"
	@echo "  Client (React) → [Subscription Key] → APIM → [No Auth] → Function App"
	@echo "  Auth termination: APIM"
	@echo "  Backend auth: none (Function App trusts APIM)"
	@echo ""

check-env:
	@echo "Checking environment variables..."
	@if [ -z "$$ARM_SUBSCRIPTION_ID" ]; then \
		echo "❌ ARM_SUBSCRIPTION_ID is not set"; \
		exit 1; \
	fi
	@if [ -z "$$ARM_TENANT_ID" ]; then \
		echo "❌ ARM_TENANT_ID is not set"; \
		exit 1; \
	fi
	@echo "✅ ARM_SUBSCRIPTION_ID: $$ARM_SUBSCRIPTION_ID"
	@echo "✅ ARM_TENANT_ID: $$ARM_TENANT_ID"
	@echo "✅ PERSONAL_SUB_REGION: $(PERSONAL_SUB_REGION)"
	@echo "✅ RESOURCE_GROUP: $(RESOURCE_GROUP)"

# Terragrunt lifecycle commands
init:
	@echo "Initializing Terragrunt..."
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) init

plan:
	@echo "Running Terragrunt plan..."
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) plan

apply:
	@echo "Applying Terragrunt changes..."
	@echo "⏱️  Note: APIM provisioning takes ~37 minutes on first deployment"
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) apply

destroy:
	@echo "Destroying infrastructure..."
	@echo "⚠️  Warning: This will destroy APIM (takes ~15 minutes)"
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) destroy

validate:
	@echo "Validating Terraform configuration..."
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) validate

reconfigure: clean-cache
	@echo "Cleaned cache. Run 'make init' to reinitialize."

clean-cache:
	@echo "Removing Terragrunt cache..."
	@rm -rf .terragrunt-cache
	@echo "✅ Cache cleaned"

unlock:
	@if [ -z "$(LOCK_ID)" ]; then \
		echo "❌ LOCK_ID required. Usage: make unlock LOCK_ID=<lock-id>"; \
		exit 1; \
	fi
	@echo "Force unlocking state with ID: $(LOCK_ID)"
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) force-unlock -force $(LOCK_ID)

# Deployment commands
deploy-function:
	@if [ -z "$(FUNCTION_APP_NAME)" ]; then \
		echo "❌ FUNCTION_APP_NAME not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Deploying Function App: $(FUNCTION_APP_NAME)"
	@echo "Auth Method: none (protected by APIM)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(SCRIPTS_DIR)/build-function-zip.sh $(STACK_DIR)/function-app.zip
	@echo "Deploying to Azure..." && \
		$(AZ) functionapp deployment source config-zip \
			--resource-group $(RESOURCE_GROUP) \
			--name $(FUNCTION_APP_NAME) \
			--src $(STACK_DIR)/function-app.zip \
			--build-remote true \
			--timeout 600 && \
		rm -f $(STACK_DIR)/function-app.zip && \
		echo "✅ Function App deployed successfully"

deploy-frontend:
	@if [ -z "$(WEB_APP_NAME)" ]; then \
		echo "❌ WEB_APP_NAME not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@if [ -z "$(APIM_API_URL)" ]; then \
		echo "❌ APIM_API_URL not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Deploying React Frontend: $(WEB_APP_NAME)"
	@echo "APIM API URL: $(APIM_API_URL)"
	@echo "Auth Method: none (APIM handles subscription key)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@# Use shared build-deployment-zip.sh script
	@API_BASE_URL=$(APIM_API_URL) $(SCRIPTS_DIR)/build-deployment-zip.sh $(STACK_DIR)/react-app.zip
	@echo "Deploying to Azure App Service (Oryx build enabled)..." && \
		$(AZ) webapp deploy \
			--resource-group $(RESOURCE_GROUP) \
			--name $(WEB_APP_NAME) \
			--src-path $(STACK_DIR)/react-app.zip \
			--type zip && \
		rm -f $(STACK_DIR)/react-app.zip && \
		echo "✅ Frontend deployed successfully" && \
		echo "🌐 Web App URL: https://$(WEB_APP_NAME).azurewebsites.net"

deploy-all: deploy-function deploy-frontend
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✅ Full stack deployment complete!"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@make show-resources

# Utility commands
show-resources:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Deployed Resources"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@if [ -n "$(APIM_NAME)" ]; then \
		echo "APIM:         $(APIM_NAME)"; \
		echo "  Gateway:    $(APIM_GATEWAY_URL)"; \
		echo "  API:        $(APIM_API_URL)"; \
	else \
		echo "APIM:         Not deployed yet"; \
	fi
	@if [ -n "$(WEB_APP_NAME)" ]; then \
		echo "Web App:      $(WEB_APP_NAME)"; \
		echo "  URL:        https://$(WEB_APP_NAME).azurewebsites.net"; \
	else \
		echo "Web App:      Not deployed yet"; \
	fi
	@if [ -n "$(FUNCTION_APP_NAME)" ]; then \
		echo "Function App: $(FUNCTION_APP_NAME)"; \
		echo "  URL:        https://$(FUNCTION_APP_NAME).azurewebsites.net"; \
		echo "  Note:       Direct access restricted if IP enforcement enabled"; \
	else \
		echo "Function App: Not deployed yet"; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

get-subscription-key:
	@if [ -z "$(APIM_SUBSCRIPTION_KEY)" ]; then \
		echo "❌ APIM subscription key not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "APIM Subscription Key"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Primary Key: $(APIM_SUBSCRIPTION_KEY)"
	@echo ""
	@echo "Use in API calls:"
	@echo "  curl -H 'Ocp-Apim-Subscription-Key: $(APIM_SUBSCRIPTION_KEY)' \\"
	@echo "    $(APIM_API_URL)/api/v1/health"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test-apim:
	@if [ -z "$(APIM_API_URL)" ] || [ -z "$(APIM_SUBSCRIPTION_KEY)" ]; then \
		echo "❌ APIM not deployed yet. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "Testing API via APIM gateway..."
	@echo "URL: $(APIM_API_URL)/api/v1/health"
	@status=$$(curl -s -o /dev/null -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $(APIM_SUBSCRIPTION_KEY)" "$(APIM_API_URL)/api/v1/health"); \
	if [ "$$status" -eq 200 ]; then \
		echo "✅ APIM Gateway: Status $$status (working)"; \
	else \
		echo "❌ APIM Gateway unreachable (Status: $$status)"; \
		exit 1; \
	fi

test-direct:
	@if [ -z "$(FUNCTION_APP_NAME)" ]; then \
		echo "❌ Function App not deployed yet. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "Testing direct Function App access (should fail if IP restrictions enforced)..."
	@echo "URL: https://$(FUNCTION_APP_NAME).azurewebsites.net/api/v1/health"
	@status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$(FUNCTION_APP_NAME).azurewebsites.net/api/v1/health"); \
	if [ "$$status" -eq 403 ]; then \
		echo "✅ Direct access blocked (Status $$status) - IP restrictions working!"; \
	elif [ "$$status" -eq 200 ]; then \
		echo "⚠️  Direct access allowed (Status $$status) - IP restrictions NOT enforced"; \
		echo "    Set security.enforce_apim_only_access = true to enable"; \
	else \
		echo "❌ Unexpected status: $$status"; \
		exit 1; \
	fi

test-endpoints: test-apim
	@if [ -z "$(WEB_APP_NAME)" ]; then \
		echo "❌ Web App not deployed yet. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "Testing Web App..."
	@echo "URL: https://$(WEB_APP_NAME).azurewebsites.net"
	@status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$(WEB_APP_NAME).azurewebsites.net"); \
	if [ "$$status" -eq 200 ]; then \
		echo "✅ Web App: Status $$status (working)"; \
	else \
		echo "❌ Web App unreachable (Status: $$status)"; \
		exit 1; \
	fi
	@echo ""
	@echo "✅ All endpoints tested successfully!"
