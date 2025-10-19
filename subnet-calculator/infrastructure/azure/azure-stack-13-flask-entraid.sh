#!/usr/bin/env bash
#
# stack-13-flask-entraid.sh - Deploy Stack 13: Flask with Entra ID Authentication
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ User → Entra ID Login               │
#   └──────────────┬──────────────────────┘
#                  │
#   ┌──────────────▼──────────────────────┐
#   │ App Service (Python Flask)          │
#   │ - TypeScript-free (pure Python)     │
#   │ - MSAL library for Entra ID         │
#   │ - OAuth 2.0 Authorization Code Flow │
#   │ - Full control over auth flow       │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS (direct call)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Public endpoint                   │
#   │ - NO AUTHENTICATION                 │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: Python Flask with MSAL + Entra ID
#   - Backend: Function App (public, no auth)
#   - Authentication: Entra ID with OAuth 2.0
#   - Use case: Debug Entra ID flows, full control
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" AZURE_TENANT_ID="xxx" ./stack-13-flask-entraid.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret
#   AZURE_TENANT_ID      - Entra ID tenant ID
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   API_BASE_URL         - Backend API URL (auto-detected or required)

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

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-entraid-flask}"
readonly APP_SERVICE_NAME="${APP_SERVICE_NAME:-app-subnet-calc-entraid-flask}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-plan-subnet-calc-entraid}"
readonly LOCATION="${LOCATION:-uksouth}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 13: Flask + Entra ID (Debugging)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: Python Flask (MSAL + Entra ID)"
log_info "  Backend:  Function App (public, NO auth)"
log_info "  Auth:     Entra ID OAuth 2.0 Code Flow"
log_info "  Cost:     ~\$10-15/month (App Service B1 + Consumption)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Purpose: Debug Entra ID authentication with full control"
log_info ""
log_info "========================================="
echo ""

# Check required environment variables
if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
  log_error "AZURE_CLIENT_ID environment variable required"
  log_error "Set it with: export AZURE_CLIENT_ID=\"your-app-id\""
  exit 1
fi

if [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_error "AZURE_CLIENT_SECRET environment variable required"
  log_error "Set it with: export AZURE_CLIENT_SECRET=\"your-secret\""
  exit 1
fi

if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
  log_error "AZURE_TENANT_ID environment variable required"
  log_error "Set it with: export AZURE_TENANT_ID=\"your-tenant-id\""
  exit 1
fi

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
log_info "Entra ID Tenant: ${AZURE_TENANT_ID}"
log_info "Entra ID Client ID: ${AZURE_CLIENT_ID}"
echo ""

read -r -p "Proceed with deployment? (Y/n): " confirm
confirm=${confirm:-y}
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  log_info "Cancelled"
  exit 0
fi
echo ""

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
  echo ""
fi

# Step 1: Create or get App Service Plan
log_step "Step 1/4: Setting up App Service Plan..."
echo ""

PLAN_EXISTS=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${PLAN_EXISTS}" -gt 0 ]]; then
  PLAN_NAME=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" \
    --query "[0].name" -o tsv)
  log_info "Using existing App Service Plan: ${PLAN_NAME}"
else
  log_info "Creating new App Service Plan: ${APP_SERVICE_PLAN_NAME}"
  az appservice plan create \
    --name "${APP_SERVICE_PLAN_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --sku B1 \
    --is-linux \
    --output none
  PLAN_NAME="${APP_SERVICE_PLAN_NAME}"
fi
echo ""

# Step 2: Create App Service
log_step "Step 2/4: Creating App Service..."
echo ""

az webapp create \
  --resource-group "${RESOURCE_GROUP}" \
  --plan "${PLAN_NAME}" \
  --name "${APP_SERVICE_NAME}" \
  --runtime "PYTHON:3.11" \
  --startup-file "gunicorn --bind 0.0.0.0:8000 --workers 2 app:app" \
  --output none

APP_URL=$(az webapp show --resource-group "${RESOURCE_GROUP}" --name "${APP_SERVICE_NAME}" \
  --query "defaultHostName" -o tsv)
APP_FULL_URL="https://${APP_URL}"

log_info "App Service created: ${APP_FULL_URL}"
echo ""

# Step 3: Configure App Settings
log_step "Step 3/4: Configuring Entra ID settings..."
echo ""

# Generate secure secret key
FLASK_SECRET_KEY=$(openssl rand -hex 32)

# Get or prompt for API URL
if [[ -z "${API_BASE_URL:-}" ]]; then
  log_warn "API_BASE_URL not set. Looking for Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    API_BASE_URL="https://$(az functionapp show --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" --query "properties.defaultHostName" -o tsv)/api/v1"
    log_info "Auto-detected API: ${API_BASE_URL}"
  else
    log_error "Could not auto-detect API. Set API_BASE_URL environment variable"
    exit 1
  fi
fi

# Set app settings
az webapp config appsettings set \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${APP_SERVICE_NAME}" \
  --settings \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
    AZURE_TENANT_ID="${AZURE_TENANT_ID}" \
    REDIRECT_URI="${APP_FULL_URL}/auth/callback" \
    FLASK_SECRET_KEY="${FLASK_SECRET_KEY}" \
    FLASK_ENV="production" \
    API_BASE_URL="${API_BASE_URL}" \
    STACK_NAME="Python Flask + Entra ID" \
  --output none

log_info "App settings configured"
echo ""

# Step 4: Deploy Flask frontend
log_step "Step 4/4: Deploying Flask frontend..."
echo ""

FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-python-flask"

cd "${FRONTEND_DIR}"

# Install dependencies
log_info "Building application..."
if [[ ! -d ".venv" ]]; then
  uv sync --no-dev
fi

# Create deployment package
log_info "Creating deployment package..."
cd "${FRONTEND_DIR}"

# Create zip file
zip -r -q /tmp/flask-app.zip . \
  -x ".venv/*" ".pytest_cache/*" ".git/*" "__pycache__/*" ".ruff_cache/*" "*.pyc" ".venv*"

# Deploy to App Service
log_info "Uploading to Azure..."
az webapp deployment source config-zip \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${APP_SERVICE_NAME}" \
  --src-path /tmp/flask-app.zip \
  --output none

rm -f /tmp/flask-app.zip

log_info "Deployment in progress..."
sleep 30

echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 13 deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group:  ${RESOURCE_GROUP}"
log_info "  App Service:     ${APP_SERVICE_NAME}"
log_info "  App Service Plan: ${PLAN_NAME}"
log_info ""
log_info "URLs:"
log_info "  Frontend (Azure):  ${APP_FULL_URL}"
log_info "  Backend API:       ${API_BASE_URL}"
log_info ""
log_info "Authentication:"
log_info "  Provider: Entra ID (OAuth 2.0 Code Flow)"
log_info "  Tenant:   ${AZURE_TENANT_ID}"
log_info "  Client:   ${AZURE_CLIENT_ID}"
log_info ""
log_info "Test commands:"
log_info "  # Visit the app (requires Entra ID login)"
log_info "  open ${APP_FULL_URL}"
log_info ""
log_info "  # View logs"
log_info "  az webapp log tail --resource-group ${RESOURCE_GROUP} --name ${APP_SERVICE_NAME}"
log_info ""
log_info "DNS Configuration:"
log_info "  Custom Domain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  Add CNAME record in Cloudflare:"
log_info "    Name:   ${SUBDOMAIN}"
log_info "    Type:   CNAME"
log_info "    Target: ${APP_URL}"
log_info "    Proxy:  DNS only (grey cloud)"
log_info ""
log_info "Update App Registration:"
log_info "  Add web redirect URI:"
log_info "    https://${APP_URL}/auth/callback"
log_info ""
log_info "Next Steps:"
log_info "  1. Update app registration with above redirect URI"
log_info "  2. Visit ${APP_FULL_URL}"
log_info "  3. Log in with your Entra ID credentials"
log_info "  4. Check logs if anything fails (see above)"
log_info ""
log_info "Debugging:"
log_info "  View real-time logs:"
log_info "    az webapp log tail --resource-group ${RESOURCE_GROUP} --name ${APP_SERVICE_NAME} -f"
log_info ""
log_info "========================================="
echo ""
