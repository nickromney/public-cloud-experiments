# Makefile for subnet-calculator Azure infrastructure deployment
# Provides common commands for deploying to Azure

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

.DEFAULT_GOAL := help

##@ Help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)Subnet Calculator - Azure Deployment$(NC)"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$|^##@.*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; /^##@/ {printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\\n", $$1, $$2}'
	@echo ""
	@echo "Environment variables:"
	@echo "  RESOURCE_GROUP            - Azure resource group name (default: rg-subnet-calc)"
	@echo "  LOCATION                  - Azure region (auto-detected from RG)"
	@echo "  FRONTEND                  - Frontend to deploy (typescript, static, flask)"
	@echo "  DISABLE_AUTH              - Disable JWT auth on Function App (true/false)"
	@echo ""

##@ Setup

.PHONY: prerequisites
prerequisites: ## Check if all required tools are installed
	@./prerequisites.sh

.PHONY: setup
setup: prerequisites ## Interactive environment setup
	@./setup-env.sh

.PHONY: check-env
check-env: ## Verify environment variables are set
	@echo "$(YELLOW)Checking environment...$(NC)"
	@if ! az account show &>/dev/null; then \
		echo "❌ Not logged in to Azure. Run 'az login'"; \
		exit 1; \
	fi
	@echo "✓ Azure CLI: logged in"
	@if [ -z "$(RESOURCE_GROUP)" ]; then \
		echo "$(YELLOW)RESOURCE_GROUP not set. Run 'make setup' or:$(NC)"; \
		echo "  export RESOURCE_GROUP='your-resource-group'"; \
		exit 1; \
	fi
	@echo "✓ RESOURCE_GROUP: $(RESOURCE_GROUP)"
	@echo "$(GREEN)Environment ready!$(NC)"

##@ Infrastructure

.PHONY: create-swa
create-swa: check-env ## Create Azure Static Web App
	@echo "$(YELLOW)Creating Static Web App...$(NC)"
	@./00-static-web-app.sh
	@echo "$(GREEN)✓ Static Web App created$(NC)"

.PHONY: create-storage
create-storage: check-env ## Create Azure Storage Account with static website
	@echo "$(YELLOW)Creating Storage Account with static website...$(NC)"
	@./05-static-website-storage.sh
	@echo "$(GREEN)✓ Storage Account created$(NC)"

.PHONY: create-function
create-function: check-env ## Create Azure Function App
	@echo "$(YELLOW)Creating Function App...$(NC)"
	@./10-function-app.sh
	@echo "$(GREEN)✓ Function App created$(NC)"

.PHONY: create-all
create-all: create-swa create-function ## Create all infrastructure (SWA + Function)
	@echo "$(GREEN)✓ All infrastructure created!$(NC)"
	@echo ""
	@echo "Next steps:"
	@echo "  make deploy-typescript  # Deploy TypeScript frontend"
	@echo "  make deploy-api         # Deploy Function API"

##@ Deployment

.PHONY: deploy-typescript
deploy-typescript: check-env ## Deploy TypeScript Vite frontend to SWA
	@echo "$(YELLOW)Deploying TypeScript frontend...$(NC)"
	@FRONTEND=typescript ./20-deploy-frontend.sh
	@echo "$(GREEN)✓ Frontend deployed$(NC)"

.PHONY: deploy-static
deploy-static: check-env ## Deploy static HTML frontend to SWA
	@echo "$(YELLOW)Deploying static HTML frontend...$(NC)"
	@FRONTEND=static ./20-deploy-frontend.sh
	@echo "$(GREEN)✓ Frontend deployed$(NC)"

.PHONY: deploy-storage
deploy-storage: check-env ## Deploy static HTML to Storage static website
	@echo "$(YELLOW)Deploying static HTML to Storage...$(NC)"
	@./25-deploy-static-website-storage.sh
	@echo "$(GREEN)✓ Static website deployed$(NC)"

.PHONY: deploy-api
deploy-api: check-env ## Deploy Function API (without auth)
	@echo "$(YELLOW)Deploying Function API...$(NC)"
	@DISABLE_AUTH=true ./21-deploy-function.sh
	@echo "$(GREEN)✓ API deployed$(NC)"

.PHONY: deploy-api-auth
deploy-api-auth: check-env ## Deploy Function API (with JWT auth)
	@echo "$(YELLOW)Deploying Function API with JWT auth...$(NC)"
	@./21-deploy-function.sh
	@echo "$(GREEN)✓ API deployed$(NC)"
	@echo "$(YELLOW)Don't forget to set JWT_SECRET_KEY!$(NC)"

.PHONY: deploy-all
deploy-all: deploy-typescript deploy-api ## Deploy everything (TypeScript + API)
	@echo "$(GREEN)✓ Full deployment complete!$(NC)"
	@echo ""
	@echo "Test your deployment:"
	@echo "  make test-api"
	@echo "  make show-urls"

##@ Production Stacks

.PHONY: deploy-stack3
deploy-stack3: check-env ## Deploy Stack 3: SWA TypeScript (No Auth)
	@echo "$(YELLOW)Deploying Stack 3: SWA TypeScript (No Auth)...$(NC)"
	@./stack-03-swa-typescript-noauth.sh

.PHONY: deploy-stack4
deploy-stack4: check-env ## Deploy Stack 4: SWA TypeScript (JWT Auth)
	@echo "$(YELLOW)Deploying Stack 4: SWA TypeScript (JWT Auth)...$(NC)"
	@./stack-04-swa-typescript-jwt.sh

.PHONY: deploy-stack5
deploy-stack5: check-env ## Deploy Stack 5: SWA TypeScript (Entra ID)
	@echo "$(YELLOW)Deploying Stack 5: SWA TypeScript (Entra ID)...$(NC)"
	@./stack-05-swa-typescript-entraid.sh

.PHONY: deploy-stack6
deploy-stack6: check-env ## Deploy Stack 6: Flask App Service
	@echo "$(YELLOW)Deploying Stack 6: Flask App Service...$(NC)"
	@./stack-06-flask-appservice.sh

.PHONY: deploy-production-all
deploy-production-all: ## Deploy all production stacks (3, 4, 5, 6)
	@echo "$(YELLOW)Deploying all production stacks...$(NC)"
	@make deploy-stack3
	@make deploy-stack4
	@make deploy-stack5
	@make deploy-stack6
	@echo "$(GREEN)✓ All production stacks deployed!$(NC)"

##@ Testing

.PHONY: test-api
test-api: check-env ## Test Function API health endpoint
	@echo "$(YELLOW)Testing Function API...$(NC)"
	@FUNC_URL=$$(az functionapp show \
		--name $${FUNCTION_APP_NAME:-func-subnet-calc} \
		--resource-group $(RESOURCE_GROUP) \
		--query defaultHostName -o tsv 2>/dev/null) && \
	if [ -n "$$FUNC_URL" ]; then \
		echo "Calling https://$$FUNC_URL/api/v1/health"; \
		curl -s "https://$$FUNC_URL/api/v1/health" | jq . || curl -s "https://$$FUNC_URL/api/v1/health"; \
		echo ""; \
		echo "$(GREEN)✓ API is responding$(NC)"; \
	else \
		echo "$(YELLOW)Function App not found. Run 'make create-function' first.$(NC)"; \
	fi

.PHONY: show-urls
show-urls: check-env ## Show deployment URLs
	@echo "$(YELLOW)Deployment URLs:$(NC)"
	@echo ""
	@SWA_URL=$$(az staticwebapp show \
		--name $${STATIC_WEB_APP_NAME:-swa-subnet-calc} \
		--resource-group $(RESOURCE_GROUP) \
		--query defaultHostname -o tsv 2>/dev/null) && \
	if [ -n "$$SWA_URL" ]; then \
		echo "Static Web App: https://$$SWA_URL"; \
	else \
		echo "Static Web App: Not deployed"; \
	fi
	@FUNC_URL=$$(az functionapp show \
		--name $${FUNCTION_APP_NAME:-func-subnet-calc} \
		--resource-group $(RESOURCE_GROUP) \
		--query defaultHostName -o tsv 2>/dev/null) && \
	if [ -n "$$FUNC_URL" ]; then \
		echo "Function API:   https://$$FUNC_URL"; \
		echo "API Docs:       https://$$FUNC_URL/api/v1/docs"; \
		echo "Health Check:   https://$$FUNC_URL/api/v1/health"; \
	else \
		echo "Function API:   Not deployed"; \
	fi

##@ Cleanup

.PHONY: cleanup
cleanup: check-env ## Delete all resources (keep resource group)
	@echo "$(YELLOW)Cleaning up resources...$(NC)"
	@./99-cleanup.sh
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

.PHONY: cleanup-all
cleanup-all: check-env ## Delete everything including resource group
	@echo "$(YELLOW)Deleting all resources including resource group...$(NC)"
	@DELETE_RG=true ./99-cleanup.sh
	@echo "$(GREEN)✓ Complete cleanup initiated$(NC)"

##@ Utilities

.PHONY: logs
logs: check-env ## Stream Function App logs
	@FUNC_NAME=$${FUNCTION_APP_NAME:-func-subnet-calc}; \
	echo "$(YELLOW)Streaming logs for $$FUNC_NAME...$(NC)"; \
	echo "Press Ctrl+C to stop"; \
	az functionapp log tail --name $$FUNC_NAME --resource-group $(RESOURCE_GROUP)

.PHONY: lint
lint: ## Run shellcheck on all scripts
	@echo "$(YELLOW)Running shellcheck...$(NC)"
	@shellcheck *.sh || true
	@echo "$(GREEN)✓ Shellcheck complete$(NC)"

.PHONY: list-resources
list-resources: check-env ## List all Azure resources in resource group
	@echo "$(YELLOW)Resources in $(RESOURCE_GROUP):$(NC)"
	@echo ""
	@az resource list \
		--resource-group $(RESOURCE_GROUP) \
		--query "[].{Name:name, Type:type, Location:location}" \
		-o table

##@ Quick Workflows

.PHONY: quick-deploy
quick-deploy: create-all deploy-all ## Quick: Create + deploy everything
	@echo "$(GREEN)✓ Quick deployment complete!$(NC)"
	@make show-urls

.PHONY: sandbox-deploy
sandbox-deploy: ## Quick deploy for Pluralsight sandbox
	@echo "$(GREEN)Starting sandbox deployment...$(NC)"
	@echo ""
	@if [ -z "$(RESOURCE_GROUP)" ]; then \
		echo "$(YELLOW)Setting up environment...$(NC)"; \
		./setup-env.sh; \
		echo ""; \
		echo "$(YELLOW)Please run the export command above, then run:$(NC)"; \
		echo "  make sandbox-deploy"; \
		exit 1; \
	fi
	@make create-all
	@echo ""
	@echo "$(YELLOW)Waiting 30 seconds for resources to be ready...$(NC)"
	@sleep 30
	@make deploy-all
	@echo ""
	@make show-urls
	@echo ""
	@echo "$(GREEN)✓ Sandbox deployment complete!$(NC)"
