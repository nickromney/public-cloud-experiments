#!/usr/bin/env bash
#
# stack-06-flask-appservice.sh - Deploy Stack 06: Flask on App Service
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure App Service (Linux)           │
#   │ - Python Flask                      │
#   │ - Server-side rendering             │
#   │ - Handles JWT auth flow             │
#   │ - Backend calls hidden from user    │
#   │ - Runs on App Service Plan          │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS + JWT token (server-side)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - REQUIRES JWT TOKEN                │
#   │ - Validates HS256 signature         │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: Python Flask (server-side rendering, App Service)
#   - Backend: Function App (Consumption plan, JWT required)
#   - Authentication: JWT tokens - handled server-side by Flask
#   - Use case: Traditional web app, server-side rendering
#   - Cost: ~$13/month (App Service Plan B1)
#
# Usage:
#   ./stack-06-flask-appservice.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-06-flask-appservice.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   APP_SERVICE_NAME     - App Service name (default: app-flask-subnet-calc)
#   APP_SERVICE_PLAN_NAME - App Service Plan name (auto-detected or creates new)
#   FUNCTION_APP_NAME    - Function App name (auto-detected or creates new)
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: flask)
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

# Configuration
readonly LOCATION="${LOCATION:-uksouth}"
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-flask}"
readonly APP_SERVICE_NAME="${APP_SERVICE_NAME:-app-flask-subnet-calc}"
readonly PLAN_SKU="${PLAN_SKU:-B1}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 06: Flask on App Service"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: Python Flask (server-side rendering)"
log_info "  Backend:  Function App (Consumption, JWT)"
log_info "  Hosting:  Azure App Service (B1 plan)"
log_info "  Auth:     JWT - handled server-side"
log_info "  Cost:     ~\$13/month (B1 plan)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure App Service Plan (B1)"
log_info "  2. Azure Function App (Consumption, JWT)"
log_info "  3. Azure App Service (Flask app)"
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

log_warn "Cost Warning:"
log_warn "  App Service Plan B1: ~\$13/month (runs 24/7)"
log_warn "  This is significantly more expensive than Free tier SWA stacks"
echo ""

read -r -p "Proceed with deployment? (Y/n): " confirm
confirm=${confirm:-y}
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  log_info "Cancelled"
  exit 0
fi
echo ""

# Extract or set RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  RG_COUNT=$(az group list --query "length(@)" -o tsv)
  if [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected resource group: ${RESOURCE_GROUP}"
  else
    log_error "Could not auto-detect resource group. Please set RESOURCE_GROUP environment variable."
    exit 1
  fi
fi

# Step 1: Create/verify App Service Plan
log_step "Step 1/4: Creating Azure App Service Plan (B1)..."
echo ""

export RESOURCE_GROUP
export LOCATION
export PLAN_SKU

"${SCRIPT_DIR}/12-create-app-service-plan.sh"

# Get App Service Plan name
if [[ -z "${APP_SERVICE_PLAN_NAME:-}" ]]; then
  PLAN_COUNT=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${PLAN_COUNT}" -eq 1 ]]; then
    APP_SERVICE_PLAN_NAME=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Using App Service Plan: ${APP_SERVICE_PLAN_NAME}"
  else
    APP_SERVICE_PLAN_NAME="plan-subnet-calc"
    log_info "Using default App Service Plan name: ${APP_SERVICE_PLAN_NAME}"
  fi
fi

export APP_SERVICE_PLAN_NAME
echo ""

# Step 2: Create Function App
log_step "Step 2/4: Creating Azure Function App..."
echo ""

"${SCRIPT_DIR}/10-function-app.sh"

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
  --query defaultHostName -o tsv 2>/dev/null || echo "")"

if [[ "${FUNCTION_APP_URL}" == "https://" ]]; then
  log_error "Failed to get Function App URL"
  exit 1
fi

log_info "Function App created: ${FUNCTION_APP_URL}"
export FUNCTION_APP_NAME
echo ""

# Step 3: Deploy Function App with JWT
log_step "Step 3/4: Deploying Function App with JWT authentication..."
echo ""

unset DISABLE_AUTH  # Enable JWT auth

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

# Generate and set JWT secret key
log_info "Configuring JWT secret key..."
JWT_SECRET_KEY=$(openssl rand -base64 32)

az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings "JWT_SECRET_KEY=${JWT_SECRET_KEY}" \
  --output none

log_info "Function App deployed with JWT authentication"
echo ""

# Wait for Function App to be ready
log_info "Waiting for Function App to be ready (30 seconds)..."
sleep 30

# Step 4: Deploy Flask App Service
log_step "Step 4/4: Deploying Flask application to App Service..."
echo ""

export APP_SERVICE_NAME
export API_BASE_URL="${FUNCTION_APP_URL}"
export JWT_SECRET_KEY

"${SCRIPT_DIR}/50-deploy-flask-app-service.sh"

# Get App Service URL
APP_SERVICE_URL="https://$(az webapp show \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")"

if [[ "${APP_SERVICE_URL}" == "https://" ]]; then
  log_error "Failed to get App Service URL"
  exit 1
fi

log_info "Flask App Service deployed: ${APP_SERVICE_URL}"
echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 06 deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group:     ${RESOURCE_GROUP}"
log_info "  App Service Plan:   ${APP_SERVICE_PLAN_NAME} (B1)"
log_info "  Function App:       ${FUNCTION_APP_NAME}"
log_info "  Flask App Service:  ${APP_SERVICE_NAME}"
log_info ""
log_info "URLs:"
log_info "  Flask Frontend:    ${APP_SERVICE_URL}"
log_info "  Backend API:       ${FUNCTION_APP_URL}"
log_info "  API Docs:          ${FUNCTION_APP_URL}/api/v1/docs"
log_info ""
log_info "Authentication:"
log_info "  Method:     JWT (server-side)"
log_info "  Flask handles authentication and token management"
log_info "  Login at:   ${APP_SERVICE_URL}/login"
log_info ""
log_info "DNS Configuration:"
log_info "  Custom Domain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  Add CNAME record in Cloudflare:"
log_info "    Name:   ${SUBDOMAIN}"
log_info "    Type:   CNAME"
log_info "    Target: ${APP_SERVICE_NAME}.azurewebsites.net"
log_info "    Proxy:  DNS only (grey cloud)"
log_info ""
log_info "  After DNS propagation, configure custom domain on App Service:"
log_info "    az webapp config hostname add \\"
log_info "      --webapp-name ${APP_SERVICE_NAME} \\"
log_info "      --resource-group ${RESOURCE_GROUP} \\"
log_info "      --hostname ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Test commands:"
log_info "  # Open Flask frontend in browser (Azure URL)"
log_info "  open ${APP_SERVICE_URL}"
log_info ""
log_info "  # Open Flask frontend in browser (Custom domain - after DNS)"
log_info "  open https://${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  # Test Function API directly"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "Architecture summary:"
log_info "  - Flask frontend (server-side rendering)"
log_info "  - App Service hosting (B1 plan)"
log_info "  - Function App API (Consumption, JWT)"
log_info "  - JWT authentication (server-side, tokens not visible to browser)"
log_info "  - Cost: ~\$13/month (B1 plan runs 24/7)"
log_info ""
log_info "Cost breakdown:"
log_info "  - App Service Plan B1: ~\$13.00/month"
log_info "  - Function App:        ~\$0.00 (Consumption, minimal usage)"
log_info "  - Total:               ~\$13.00/month"
log_info ""
log_info "Note: Deployment may take 1-2 minutes to complete."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
