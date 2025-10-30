#!/usr/bin/env bash
#
# stack-02-flask-jwt.sh - Deploy complete Stack 02: Flask + JWT (Public with VNet)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Flask App (Azure App Service)       │
#   │ - Python Flask                      │
#   │ - Server-side rendering             │
#   │ - Handles JWT auth flow             │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS + JWT token
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (App Svc Plan)   │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - REQUIRES JWT TOKEN                │
#   │ - VNet integrated (outbound)        │
#   └──────────────┬──────────────────────┘
#                  │ Outbound only
#   ┌──────────────▼──────────────────────┐
#   │ Azure Virtual Network                │
#   │ - 10.0.0.0/16 address space         │
#   │ - Function subnet (10.0.1.0/28)     │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: Python Flask (server-side rendering, App Service)
#   - Backend: Function App (App Service Plan B1, VNet integrated)
#   - Networking: VNet for outbound routing
#   - Authentication: JWT tokens - API requires valid token
#   - Cost: ~$0.07 for 4-hour sandbox (B1 plan ~$0.018/hour)
#
# Usage:
#   ./stack-02-flask-jwt.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   VNET_NAME            - VNet name (default: vnet-subnet-calc)
#   APP_SERVICE_PLAN_NAME - App Service Plan name (default: plan-subnet-calc)
#   FUNCTION_APP_NAME    - Function App name (default: func-subnet-calc-{random})
#   APP_SERVICE_NAME     - Flask App Service name (default: app-flask-subnet-calc)
#   JWT_USERNAME         - JWT username (default: admin)
#   JWT_PASSWORD         - JWT password (default: subnet-calc-2024)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Banner
echo ""
log_info "========================================="
log_info "Stack 02: Flask + JWT (Public with VNet)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: Flask App (App Service)"
log_info "  Backend:  Function App (App Service Plan B1 + VNet)"
log_info "  Auth:     JWT tokens required"
log_info "  Cost:     ~\$0.07 for 4-hour sandbox"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure VNet (10.0.0.0/16)"
log_info "  2. App Service Plan (B1 Basic tier)"
log_info "  3. Function App on App Service Plan (VNet integrated)"
log_info "  4. Flask App Service (with JWT auth)"
log_info "  5. JWT authentication (Function ← → Flask)"
log_info ""
log_info "Backend API calls are hidden from end users (server-side)."
log_info ""
log_info "========================================="
echo ""

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Show current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
log_info "Current subscription: ${SUBSCRIPTION_NAME}"
log_info "Subscription ID: ${SUBSCRIPTION_ID}"
echo ""

read -r -p "Proceed with deployment? (Y/n): " confirm
confirm=${confirm:-y}
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  log_info "Cancelled"
  exit 0
fi
echo ""

# Auto-detect or prompt for RESOURCE_GROUP before calling subscripts
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    log_error "Create one with: az group create --name rg-subnet-calc --location uksouth"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    # Source selection utilities
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
  echo ""
fi

# Generate shared JWT secret
export JWT_SECRET_KEY="${JWT_SECRET_KEY:-$(openssl rand -base64 32)}"
export JWT_USERNAME="${JWT_USERNAME:-admin}"
export JWT_PASSWORD="${JWT_PASSWORD:-subnet-calc-2024}"
export JWT_ALGORITHM="${JWT_ALGORITHM:-HS256}"

log_info "Generated JWT configuration:"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info "  Algorithm: ${JWT_ALGORITHM}"
log_info "  Secret: ${JWT_SECRET_KEY:0:20}... (truncated)"
echo ""

# Step 1: Create VNet infrastructure
log_step "Step 1/6: Creating Azure Virtual Network infrastructure..."
echo ""

export RESOURCE_GROUP
"${SCRIPT_DIR}/11-create-vnet-infrastructure.sh"

if [[ -z "${VNET_NAME:-}" ]]; then
  VNET_COUNT=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${VNET_COUNT}" -eq 1 ]]; then
    VNET_NAME=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  else
    VNET_NAME="vnet-subnet-calc"
  fi
fi

log_info "VNet created: ${VNET_NAME}"
echo ""

# Step 2: Create App Service Plan (B1 tier for VNet support)
log_step "Step 2/6: Creating App Service Plan (B1 tier)..."
echo ""

export PLAN_SKU=B1
"${SCRIPT_DIR}/12-create-app-service-plan.sh"

# Extract App Service Plan details
if [[ -z "${APP_SERVICE_PLAN_NAME:-}" ]]; then
  PLAN_COUNT=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${PLAN_COUNT}" -eq 1 ]]; then
    APP_SERVICE_PLAN_NAME=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  else
    APP_SERVICE_PLAN_NAME="plan-subnet-calc"
  fi
fi

log_info "App Service Plan created: ${APP_SERVICE_PLAN_NAME} (B1)"
echo ""

# Step 3: Create Function App on App Service Plan
log_step "Step 3/6: Creating Function App on App Service Plan..."
echo ""

export APP_SERVICE_PLAN_NAME
"${SCRIPT_DIR}/13-create-function-app-on-app-service-plan.sh"

# Extract Function App details
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
    # Get the most recently created Function App
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" \
      --query "sort_by(@, &lastModifiedTimeUtc)[-1].name" -o tsv)
  else
    log_error "No Function App found after creation"
    exit 1
  fi
fi

FUNCTION_APP_URL="https://$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv 2>/dev/null || echo "")"

log_info "Function App created: ${FUNCTION_APP_NAME}"
log_info "URL: ${FUNCTION_APP_URL}"
echo ""

# Step 4: Configure Function App VNet integration
log_step "Step 4/6: Configuring Function App VNet integration..."
echo ""

export VNET_NAME
export FUNCTION_APP_NAME
"${SCRIPT_DIR}/14-configure-function-vnet-integration.sh"

log_info "Function App integrated with VNet"
echo ""

# Step 5: Deploy Function App code with JWT authentication
log_step "Step 5/6: Deploying Function App code (JWT authentication)..."
echo ""

export RESOURCE_GROUP
export FUNCTION_APP_NAME
export DISABLE_AUTH=false
export JWT_SECRET_KEY
export JWT_ALGORITHM

# Configure JWT settings on Function App
log_info "Configuring JWT authentication settings..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    JWT_SECRET_KEY="${JWT_SECRET_KEY}" \
    JWT_ALGORITHM="${JWT_ALGORITHM}" \
  --output none

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed with JWT authentication"
echo ""

# Wait for Function App to be fully ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 6: Deploy Flask frontend to App Service
log_step "Step 6/6: Deploying Flask frontend to App Service..."
echo ""

export APP_SERVICE_NAME="${APP_SERVICE_NAME:-app-flask-subnet-calc}"
export API_BASE_URL="${FUNCTION_APP_URL}"
export JWT_USERNAME
export JWT_PASSWORD
export JWT_SECRET_KEY
export JWT_ALGORITHM

"${SCRIPT_DIR}/50-deploy-flask-app-service.sh"

# Get Flask App Service URL
FLASK_APP_URL="https://$(az webapp show \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv 2>/dev/null || echo "")"

log_info "Flask App deployed: ${FLASK_APP_URL}"
echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 02 deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  VNet:           ${VNET_NAME}"
log_info "  App Svc Plan:   ${APP_SERVICE_PLAN_NAME} (B1)"
log_info "  Function App:   ${FUNCTION_APP_NAME}"
log_info "  Flask App:      ${APP_SERVICE_NAME}"
log_info ""
log_info "URLs:"
log_info "  Frontend (Flask): ${FLASK_APP_URL}"
log_info "  Backend API:      ${FUNCTION_APP_URL}"
log_info "  API Docs:         ${FUNCTION_APP_URL}/api/v1/docs"
log_info "  API Health:       ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "Login credentials:"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info ""
log_info "Test commands:"
log_info "  # Test API health (should require JWT)"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "  # Open Flask frontend (handles JWT automatically)"
log_info "  open ${FLASK_APP_URL}"
log_info ""
log_info "  # Login with username: ${JWT_USERNAME}, password: ${JWT_PASSWORD}"
log_info ""
log_info "Architecture summary:"
log_info "  - Flask frontend (server-side, hides backend calls)"
log_info "  - Function App (App Service Plan B1 with VNet)"
log_info "  - JWT authentication required for API"
log_info "  - Cost: ~\$0.07 for 4-hour sandbox"
log_info ""
log_info "Note: Initial deployment may take 2-3 minutes to fully propagate."
log_info "      If the frontend doesn't work immediately, wait a moment and refresh."
log_info ""
log_info "========================================="
echo ""
