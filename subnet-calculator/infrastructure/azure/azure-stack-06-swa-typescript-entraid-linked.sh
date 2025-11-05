#!/usr/bin/env bash
#
# stack-05b-swa-typescript-entraid-linked.sh - Deploy Stack 05b: Entra ID + Linked Backend (RECOMMENDED)
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
#   │ - /api/* → SWA Proxy                │
#   └──────────────┬──────────────────────┘
#                  │ Private (linked + IP restricted)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Linked to SWA                     │
#   │ - IP restricted (SWA service tag)   │
#   │ - Direct access blocked             │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (linked to SWA + IP restricted)
#   - Authentication: Entra ID on SWA (protects frontend + API via proxy)
#   - Security: IP restrictions prevent direct backend access
#   - Use case: Enterprise apps, internal tools, RECOMMENDED setup
#   - Cost: ~$9/month (Standard tier SWA + Consumption)
#
# Key Benefits:
#   - Same-origin API calls (no CORS issues)
#   - HttpOnly cookies (secure, XSS protection)
#   - API accessed via SWA proxy (Entra ID required)
#   - Defense-in-depth: Auth + IP restrictions
#   - Direct azurewebsites.net endpoint blocked
#   - Simple setup, good balance
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" ./stack-05b-swa-typescript-entraid-linked.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: entraid-linked)

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

# Source utility functions
source "${SCRIPT_DIR}/lib/map-swa-region.sh"

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-entraid-linked}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-linked}"

# Map region to SWA-compatible region (SWA only available in specific regions)
REQUESTED_LOCATION="${LOCATION:-uksouth}"
SWA_LOCATION=$(map_swa_region "${REQUESTED_LOCATION}")
readonly LOCATION="${SWA_LOCATION}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 05b: SWA TypeScript (Entra ID + Linked Backend)"
log_info "RECOMMENDED SETUP"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID protected)"
log_info "  Backend:  Function App (linked + IP restricted)"
log_info "  Auth:     Entra ID on SWA (protects frontend + API)"
log_info "  Security: IP restrictions (SWA service tag only)"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info "  Region:   ${LOCATION} (SWA mapped from ${REQUESTED_LOCATION})"
log_info ""
log_info "Key benefits:"
log_info "  ✓ Same-origin API calls (no CORS)"
log_info "  ✓ HttpOnly cookies (secure)"
log_info "  ✓ API via SWA proxy (auth required)"
log_info "  ✓ Defense-in-depth (auth + IP restrictions)"
log_info "  ✓ Direct backend access blocked"
log_info "  ✓ Simple setup"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Entra ID authentication (SWA)"
log_info "  3. Azure Function App (no auth, SWA handles it)"
log_info "  4. Link function app to SWA"
log_info "  5. Configure IP restrictions (defense-in-depth)"
log_info "  6. TypeScript Vite frontend"
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

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Show current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
log_info "Current subscription: ${SUBSCRIPTION_NAME}"
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
    log_error "No resource groups found"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected: ${RESOURCE_GROUP}"
  else
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
  fi
  echo ""
fi

# Step 1: Create Function App
log_step "Step 1/5: Creating Azure Function App..."
echo ""

export RESOURCE_GROUP
export LOCATION
FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-entraid-linked}"
export FUNCTION_APP_NAME

# Check if Function App already exists
if az webapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Using existing Function App: ${FUNCTION_APP_NAME}"
else
  log_info "Creating new Function App: ${FUNCTION_APP_NAME}"
  "${SCRIPT_DIR}/10-function-app.sh"
fi

FUNCTION_APP_URL="https://$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)"

log_info "Function App created: ${FUNCTION_APP_URL}"
echo ""

# Step 2: Deploy Function App code (no auth - SWA handles it)
log_step "Step 2/5: Deploying Function App code..."
echo ""

export FUNCTION_APP_NAME
export DISABLE_AUTH=true

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed"
sleep 30
echo ""

# Step 3: Create Static Web App
log_step "Step 3/5: Creating Azure Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export STATIC_WEB_APP_SKU="Standard"

"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 4: Link Function App to SWA
log_step "Step 4/6: Linking Function App to SWA..."
echo ""

FUNC_RESOURCE_ID=$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info "Linking ${FUNCTION_APP_NAME} to ${STATIC_WEB_APP_NAME}..."
az staticwebapp backends link \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --backend-resource-id "${FUNC_RESOURCE_ID}" \
  --backend-region "${LOCATION}" \
  --output none

log_info "Function App linked to SWA"
echo ""

# Step 5: Configure IP restrictions (defense-in-depth)
log_step "Step 5/6: Configuring IP restrictions on Function App..."
echo ""

log_info "Securing Function App backend with IP restrictions..."
log_info "This prevents direct access to azurewebsites.net endpoint"
log_info "Only Azure Static Web Apps service tag will be allowed"
echo ""

export FUNCTION_APP_NAME
export RESOURCE_GROUP

# Call IP restrictions script - it will auto-detect the Function App
"${SCRIPT_DIR}/45-configure-ip-restrictions.sh" <<EOF
y
EOF

log_info "IP restrictions applied: Function App now accessible only from SWA"
echo ""

# Step 6: Configure Entra ID and deploy frontend
log_step "Step 6/6: Configuring Entra ID and deploying frontend..."
echo ""

log_info "Setting SWA app settings for Entra ID..."
az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"

[[ ! -d "node_modules" ]] && npm install

log_info "Building with empty API URL (use /api route via SWA proxy)..."
VITE_AUTH_ENABLED=true VITE_AUTH_METHOD=entraid VITE_API_URL="" npm run build

if [[ -f "staticwebapp-entraid.config.json" ]]; then
  cp staticwebapp-entraid.config.json dist/staticwebapp.config.json
fi

DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

command -v swa &>/dev/null || npm install -g @azure/static-web-apps-cli

log_info "Deploying frontend..."
npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --api-location "" \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --env production

echo ""
log_info "========================================="
log_info "Stack 05b deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources:"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Function App:   ${FUNCTION_APP_NAME} (linked + IP restricted)"
log_info ""
log_info "URLs:"
log_info "  Frontend: https://${SWA_URL}"
log_info "  API:      https://${SWA_URL}/api/v1/health (via SWA proxy)"
log_info ""
log_info "Security Configuration:"
log_info "  ✓ Entra ID authentication (protects frontend + API)"
log_info "  ✓ Same-origin requests (/api route)"
log_info "  ✓ HttpOnly cookies (XSS protection)"
log_info "  ✓ IP restrictions configured (only Azure SWA service tag)"
log_info "  ✓ Direct backend access blocked (azurewebsites.net)"
log_info ""
log_info "Defense-in-depth:"
log_info "  - Layer 1: Entra ID authentication on SWA"
log_info "  - Layer 2: IP restrictions on Function App"
log_info "  - Backend only accessible from SWA, not directly"
log_info ""
log_info "Test frontend:"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "Test IP restrictions (should fail with 403):"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info "  Expected: 403 Forbidden - direct access denied"
log_info ""
log_info "Access via SWA (should work after login):"
log_info "  curl https://${SWA_URL}/api/v1/health"
log_info ""
log_info "========================================="
echo ""
