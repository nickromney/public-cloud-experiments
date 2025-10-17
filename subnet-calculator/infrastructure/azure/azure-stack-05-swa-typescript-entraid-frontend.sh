#!/usr/bin/env bash
#
# stack-05a-swa-typescript-entraid-frontend.sh - Deploy Stack 05a: Entra ID (Frontend Only)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ User → Entra ID Login               │
#   └──────────────┬──────────────────────┘
#                  │
#   ┌──────────────▼──────────────────────┐
#   │ Azure Static Web App (Standard)     │
#   │ - TypeScript Vite SPA               │
#   │ - Entra ID authentication           │
#   │ - Protected frontend content        │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS (direct call)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Public endpoint                   │
#   │ - NO AUTHENTICATION                 │
#   │ - Can be bypassed!                  │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (Consumption plan, public, no auth)
#   - Authentication: Entra ID on SWA only
#   - Use case: Protect frontend content, API remains public
#   - Cost: ~$9/month (Standard tier SWA + Consumption)
#
# Security Warning:
#   - Frontend is protected (Entra ID login required)
#   - API is still PUBLIC (anyone can call directly)
#   - Users can bypass frontend by calling function URL
#   - Use Stack 05b (linked backend) for better security
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" ./stack-05a-swa-typescript-entraid-frontend.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: entraid-frontend)

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
readonly SUBDOMAIN="${SUBDOMAIN:-entraid-frontend}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-frontend}"
readonly LOCATION="${LOCATION:-uksouth}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 05a: SWA TypeScript (Entra ID Frontend Only)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID protected)"
log_info "  Backend:  Function App (public, NO auth)"
log_info "  Auth:     Entra ID on SWA only"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_warn "SECURITY WARNING:"
log_warn "  - Frontend is protected (login required)"
log_warn "  - API is PUBLIC (can be bypassed)"
log_warn "  - Users can call function URL directly"
log_warn "  - Consider Stack 05b (linked backend) for better security"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Entra ID authentication (SWA)"
log_info "  3. Azure Function App (public, no auth)"
log_info "  4. TypeScript Vite frontend"
log_info ""
log_info "========================================="
echo ""

# Check required environment variables
if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
  log_error "AZURE_CLIENT_ID environment variable required"
  log_error "Set it with: export AZURE_CLIENT_ID=\"your-app-id\""
  log_error ""
  log_error "Create Entra ID app registration:"
  log_error "  1. Azure Portal → Entra ID → App registrations → New registration"
  log_error "  2. Name: Subnet Calculator SWA"
  log_error "  3. Redirect URI: https://your-swa.azurestaticapps.net/.auth/login/aad/callback"
  log_error "  4. Copy Application (client) ID"
  exit 1
fi

if [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_error "AZURE_CLIENT_SECRET environment variable required"
  log_error "Set it with: export AZURE_CLIENT_SECRET=\"your-secret\""
  log_error ""
  log_error "Create client secret:"
  log_error "  1. Azure Portal → Entra ID → App registrations → Your app"
  log_error "  2. Certificates & secrets → New client secret"
  log_error "  3. Copy the secret value"
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
    log_error "Create one with: az group create --name rg-subnet-calc --location ${LOCATION}"
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

# Step 1: Create Static Web App
log_step "Step 1/5: Creating Azure Static Web App..."
echo ""

export RESOURCE_GROUP
export STATIC_WEB_APP_NAME
export LOCATION
export STATIC_WEB_APP_SKU="Standard"

"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv 2>/dev/null || echo "")

if [[ -z "${SWA_URL}" ]]; then
  log_error "Failed to get Static Web App URL"
  exit 1
fi

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 2: Configure Entra ID on SWA
log_step "Step 2/5: Configuring Entra ID authentication on SWA..."
echo ""

log_info "Setting SWA app settings for Entra ID..."
az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

log_info "Entra ID configured on SWA"
echo ""

# Step 3: Create Function App (public, no auth)
log_step "Step 3/5: Creating Azure Function App (public, no auth)..."
echo ""

export RESOURCE_GROUP
export LOCATION
"${SCRIPT_DIR}/10-function-app.sh"

# Extract Function App details
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
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
  --query "properties.defaultHostName" -o tsv 2>/dev/null || echo "")"

if [[ "${FUNCTION_APP_URL}" == "https://" ]]; then
  log_error "Failed to get Function App URL"
  exit 1
fi

log_info "Function App created: ${FUNCTION_APP_URL}"
echo ""

# Step 4: Deploy Function App code (no authentication)
log_step "Step 4/5: Deploying Function App code (no authentication)..."
echo ""

export FUNCTION_APP_NAME
export DISABLE_AUTH=true

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed: ${FUNCTION_APP_URL}"
log_warn "Authentication: Disabled (public access - can be bypassed)"
echo ""

# Wait for Function App to be ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 5: Deploy frontend with API URL and Entra ID config
log_step "Step 5/5: Deploying TypeScript Vite frontend with Entra ID..."
echo ""

FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"

cd "${FRONTEND_DIR}"

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
  log_info "Installing npm dependencies..."
  npm install
fi

# Build frontend with function app URL
log_info "Building production bundle with API URL: ${FUNCTION_APP_URL}"
VITE_API_URL="${FUNCTION_APP_URL}" npm run build

# Copy Entra ID staticwebapp config to dist
log_info "Configuring Entra ID authentication..."
if [[ -f "staticwebapp-entraid.config.json" ]]; then
  cp staticwebapp-entraid.config.json dist/staticwebapp.config.json
  log_info "Entra ID config copied to dist/"
else
  log_error "staticwebapp-entraid.config.json not found"
  log_error "Create this file with Entra ID authentication configuration"
  exit 1
fi

# Get deployment token
log_info "Retrieving deployment token..."
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Check if SWA CLI is installed
if ! command -v swa &>/dev/null; then
  log_warn "Azure Static Web Apps CLI not found. Installing globally..."
  npm install -g @azure/static-web-apps-cli
fi

# Deploy to Static Web App (no managed functions - BYO)
log_info "Deploying frontend to Azure Static Web App..."
npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --api-location "" \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --env production

log_info "Frontend deployed: https://${SWA_URL}"
echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 05a deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Function App:   ${FUNCTION_APP_NAME}"
log_info ""
log_info "URLs:"
log_info "  Frontend (Azure):  https://${SWA_URL}"
log_info "  Backend API:       ${FUNCTION_APP_URL}"
log_info "  API Docs:          ${FUNCTION_APP_URL}/api/v1/docs"
log_info "  API Health:        ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "Authentication:"
log_info "  Frontend: Entra ID (login required)"
log_info "  Backend:  None (public access)"
log_info ""
log_warn "SECURITY WARNING:"
log_warn "  Frontend requires login, but API is public!"
log_warn "  Users can bypass by calling function URL directly:"
log_warn "    curl ${FUNCTION_APP_URL}/api/v1/health"
log_warn ""
log_warn "  This works because:"
log_warn "    - Entra ID only protects SWA resources"
log_warn "    - Function app has no authentication"
log_warn "    - Frontend calls function URL directly (visible in browser)"
log_warn ""
log_warn "  For better security, use:"
log_warn "    - Stack 05b: Linked backend (SWA proxy)"
log_warn "    - Stack 05c: Double authentication"
log_warn "    - Stack 06: Network-secured"
log_info ""
log_info "DNS Configuration:"
log_info "  Custom Domain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  Add CNAME record in Cloudflare:"
log_info "    Name:   ${SUBDOMAIN}"
log_info "    Type:   CNAME"
log_info "    Target: ${SWA_URL}"
log_info "    Proxy:  DNS only (grey cloud)"
log_info ""
log_info "Test commands:"
log_info "  # Test frontend (requires Entra ID login)"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "  # Bypass test (no auth required - security issue)"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "Architecture summary:"
log_info "  - TypeScript Vite frontend (Entra ID protected)"
log_info "  - Function App API (public, no auth)"
log_info "  - Cross-origin requests (CORS required)"
log_info "  - Frontend protected, API exposed"
log_info "  - Cost: ~\$9/month"
log_info ""
log_info "Use case:"
log_info "  - Protect frontend content/UI"
log_info "  - API data is not sensitive (can be public)"
log_info "  - Example: Documentation site with restricted access"
log_info ""
log_info "========================================="
echo ""
