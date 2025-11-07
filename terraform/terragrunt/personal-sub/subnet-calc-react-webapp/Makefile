STACK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)/../../../../)
INFRA_AZURE_DIR := $(REPO_ROOT)/subnet-calculator/infrastructure/azure
FRONTEND_REACT_DIR := $(REPO_ROOT)/subnet-calculator/frontend-react

TERRAGRUNT ?= terragrunt
RESOURCE_GROUP ?= rg-subnet-calc-webapp
PERSONAL_SUB_REGION ?= uksouth

# Resolve outputs from the current Terragrunt state (if available)
define tg-output
$(shell cd $(STACK_DIR) && PERSONAL_SUB_REGION=$(PERSONAL_SUB_REGION) $(TERRAGRUNT) output -raw $(1) 2>/dev/null)
endef

WEB_APP_NAME ?= $(call tg-output,web_app_name)
WEB_APP_PLAN_NAME ?= $(call tg-output,web_app_plan_name)
FUNCTION_APP_NAME ?= $(call tg-output,function_app_name)
API_BASE_URL ?= $(call tg-output,function_app_api_base_url)
STACK_DISPLAY_NAME ?= Subnet Calculator React (Easy Auth)

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

.PHONY: function-app-deploy web-app-deploy show-targets
.PHONY: init plan apply unlock

show-targets:
	@echo "Available targets:"
	@echo "  make function-app-deploy   # Build + deploy the FastAPI Azure Function ZIP"
	@echo "  make web-app-deploy        # Build + deploy the React frontend to App Service"
	@echo "  make init/plan/apply       # Terragrunt lifecycle helpers"

init:
	cd "$(STACK_DIR)" && PERSONAL_SUB_REGION="$(PERSONAL_SUB_REGION)" $(TERRAGRUNT) init

plan:
	cd "$(STACK_DIR)" && PERSONAL_SUB_REGION="$(PERSONAL_SUB_REGION)" $(TERRAGRUNT) plan

apply:
	cd "$(STACK_DIR)" && PERSONAL_SUB_REGION="$(PERSONAL_SUB_REGION)" $(TERRAGRUNT) apply

unlock:
	@if [ -z "$(LOCK)" ]; then \
		echo "LOCK_ID is required. Usage: make unlock LOCK_ID=<id> or make unlock <id>"; \
		exit 1; \
	fi
	cd "$(STACK_DIR)" && PERSONAL_SUB_REGION="$(PERSONAL_SUB_REGION)" $(TERRAGRUNT) force-unlock $(LOCK)

function-app-deploy:
	@if [ -z "$(FUNCTION_APP_NAME)" ]; then \
		echo "FUNCTION_APP_NAME is empty. Run 'terragrunt apply' first or set FUNCTION_APP_NAME=<name>."; \
		exit 1; \
	fi
	@echo "Deploying Azure Function '$(FUNCTION_APP_NAME)' to $(RESOURCE_GROUP) ..."
	cd "$(INFRA_AZURE_DIR)" && \
		RESOURCE_GROUP="$(RESOURCE_GROUP)" \
		FUNCTION_APP_NAME="$(FUNCTION_APP_NAME)" \
		./22-deploy-function-zip.sh

web-app-deploy:
	@if [ -z "$(WEB_APP_NAME)" ]; then \
		echo "WEB_APP_NAME is empty. Run 'terragrunt apply' first or set WEB_APP_NAME=<name>."; \
		exit 1; \
	fi
	@if [ -z "$(WEB_APP_PLAN_NAME)" ]; then \
		echo "WEB_APP_PLAN_NAME is empty. Run 'terragrunt apply' first or set WEB_APP_PLAN_NAME=<name>."; \
		exit 1; \
	fi
	@if [ -z "$(API_BASE_URL)" ]; then \
		echo "API_BASE_URL is empty. Run 'terragrunt apply' first or set API_BASE_URL=<url>."; \
		exit 1; \
	fi
	@echo "Building React frontend and deploying to App Service '$(WEB_APP_NAME)' ..."
	cd "$(INFRA_AZURE_DIR)" && \
		RESOURCE_GROUP="$(RESOURCE_GROUP)" \
		APP_SERVICE_NAME="$(WEB_APP_NAME)" \
		APP_SERVICE_PLAN_NAME="$(WEB_APP_PLAN_NAME)" \
		API_BASE_URL="$(API_BASE_URL)" \
		STACK_NAME="$(STACK_DISPLAY_NAME)" \
		FRONTEND_DIR="$(FRONTEND_REACT_DIR)" \
		./59-deploy-typescript-app-service.sh
