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
#                  │ Private (linked)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Linked to SWA                     │
#   │ - Public but proxied                │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (linked to SWA)
#   - Authentication: Entra ID on SWA (protects frontend + API via proxy)
#   - Use case: Enterprise apps, internal tools, RECOMMENDED setup
#   - Cost: ~$9/month (Standard tier SWA + Consumption)
#
# Key Benefits:
#   - Same-origin API calls (no CORS issues)
#   - HttpOnly cookies (secure, XSS protection)
#   - API accessed via SWA proxy (Entra ID required)
#   - Reasonable security for most use cases
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

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-entraid-linked}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-linked}"
readonly LOCATION="${LOCATION:-uksouth}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 05b: SWA TypeScript (Entra ID + Linked Backend)"
log_info "RECOMMENDED SETUP"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID protected)"
log_info "  Backend:  Function App (linked to SWA)"
log_info "  Auth:     Entra ID on SWA (protects frontend + API)"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Key benefits:"
log_info "  ✓ Same-origin API calls (no CORS)"
log_info "  ✓ HttpOnly cookies (secure)"
log_info "  ✓ API via SWA proxy (auth required)"
log_info "  ✓ Reasonable security"
log_info "  ✓ Simple setup"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Entra ID authentication (SWA)"
log_info "  3. Azure Function App (no auth, SWA handles it)"
log_info "  4. Link function app to SWA"
log_info "  5. TypeScript Vite frontend"
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
"${SCRIPT_DIR}/10-function-app.sh"

if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv)
  if [[ "${FUNC_COUNT}" -ge 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" \
      --query "sort_by(@, &createdTime)[-1].name" -o tsv)
  fi
fi

FUNCTION_APP_URL="https://$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv)"

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
log_step "Step 4/5: Linking Function App to SWA..."
echo ""

FUNC_RESOURCE_ID=$(az functionapp show \
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

# Step 5: Configure Entra ID and deploy frontend
log_step "Step 5/5: Configuring Entra ID and deploying frontend..."
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
VITE_API_URL="" npm run build

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
log_info "  Function App:   ${FUNCTION_APP_NAME} (linked)"
log_info ""
log_info "URLs:"
log_info "  Frontend: https://${SWA_URL}"
log_info "  API:      https://${SWA_URL}/api/v1/health (via SWA proxy)"
log_info ""
log_info "Authentication:"
log_info "  ✓ Entra ID on SWA (protects frontend + API)"
log_info "  ✓ Same-origin requests (/api route)"
log_info "  ✓ HttpOnly cookies"
log_info ""
log_info "Test:"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "Note: Direct function URL still accessible"
log_info "      ${FUNCTION_APP_URL}/api/v1/health"
log_info "      For maximum security, use Stack 06 (network secured)"
log_info ""
log_info "========================================="
echo ""
