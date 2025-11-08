.DEFAULT_GOAL := help

# Paths
STACK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)../../../..)
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
API_BASE_URL := $(call tg-output,function_app_api_base_url)

.PHONY: help check-env init plan apply destroy reconfigure validate
.PHONY: deploy-function deploy-frontend deploy-all clean-cache
.PHONY: show-resources test-endpoints unlock

help:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Subnet Calculator React Web App - Terragrunt Stack"
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
	@echo "  make deploy-function  - Build and deploy Function App backend"
	@echo "  make deploy-frontend  - Build and deploy React frontend"
	@echo "  make deploy-all       - Deploy both function and frontend"
	@echo ""
	@echo "Utilities:"
	@echo "  make show-resources   - Show deployed resource names"
	@echo "  make test-endpoints   - Test API and web app endpoints"
	@echo "  make clean-cache      - Remove Terragrunt cache"
	@echo "  make unlock LOCK_ID=<id> - Force unlock Terraform state"
	@echo ""
	@echo "Environment Variables:"
	@echo "  PERSONAL_SUB_REGION   - Azure region (default: uksouth)"
	@echo "  RESOURCE_GROUP        - Resource group name"
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
	PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) apply

destroy:
	@echo "Destroying infrastructure..."
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
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@cd $(API_FUNCTION_DIR) && \
		echo "Creating deployment package..." && \
		rm -rf .python_packages function-app.zip && \
		zip -r function-app.zip . -x "*.git*" -x "*__pycache__*" -x "*.pyc" -x "tests/*" -x ".pytest_cache/*" -x ".venv/*" -x ".ruff_cache/*" && \
		echo "Deploying to Azure..." && \
		$(AZ) functionapp deployment source config-zip \
			--resource-group $(RESOURCE_GROUP) \
			--name $(FUNCTION_APP_NAME) \
			--src function-app.zip && \
		rm -f function-app.zip && \
		echo "✅ Function App deployed successfully"

deploy-frontend:
	@if [ -z "$(WEB_APP_NAME)" ]; then \
		echo "❌ WEB_APP_NAME not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@if [ -z "$(API_BASE_URL)" ]; then \
		echo "❌ API_BASE_URL not found. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Deploying React Frontend: $(WEB_APP_NAME)"
	@echo "API Base URL: $(API_BASE_URL)"
	@echo "Auth Method: JWT (see terraform.tfvars for credentials)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@cd $(FRONTEND_REACT_DIR) && \
		echo "Installing dependencies..." && \
		npm install && \
		echo "Building React app with API_BASE_URL=$(API_BASE_URL) and AUTH_METHOD=jwt..." && \
		VITE_API_BASE_URL=$(API_BASE_URL) VITE_AUTH_METHOD=jwt npm run build && \
		echo "Creating deployment package..." && \
		zip -r react-app.zip dist package.json package-lock.json server.js -x "*/test-results/*" -x "*/playwright-report/*" && \
		echo "Deploying to Azure App Service..." && \
		$(AZ) webapp deploy \
			--resource-group $(RESOURCE_GROUP) \
			--name $(WEB_APP_NAME) \
			--src-path react-app.zip \
			--type zip && \
		rm -f react-app.zip && \
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
	@if [ -n "$(WEB_APP_NAME)" ]; then \
		echo "Web App:      $(WEB_APP_NAME)"; \
		echo "  URL:        https://$(WEB_APP_NAME).azurewebsites.net"; \
	else \
		echo "Web App:      Not deployed yet"; \
	fi
	@if [ -n "$(FUNCTION_APP_NAME)" ]; then \
		echo "Function App: $(FUNCTION_APP_NAME)"; \
		echo "  URL:        https://$(FUNCTION_APP_NAME).azurewebsites.net"; \
		echo "  API:        $(API_BASE_URL)"; \
	else \
		echo "Function App: Not deployed yet"; \
	fi
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test-endpoints:
	@if [ -z "$(API_BASE_URL)" ] || [ -z "$(WEB_APP_NAME)" ]; then \
		echo "❌ Resources not deployed yet. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "Testing endpoints..."
	@echo "API Health: $(API_BASE_URL)/health"
	@status=$$(curl -s -o /dev/null -w "%{http_code}" "$(API_BASE_URL)/health"); \
	if [ "$$status" -eq 200 ]; then \
		echo "✅ Status: $$status"; \
	else \
		echo "❌ API unreachable (Status: $$status)"; \
		exit 1; \
	fi
	@echo "Web App: https://$(WEB_APP_NAME).azurewebsites.net"
	@status=$$(curl -s -o /dev/null -w "%{http_code}" "https://$(WEB_APP_NAME).azurewebsites.net"); \
	if [ "$$status" -eq 200 ]; then \
		echo "✅ Status: $$status"; \
	else \
		echo "❌ Web App unreachable (Status: $$status)"; \
		exit 1; \
	fi
