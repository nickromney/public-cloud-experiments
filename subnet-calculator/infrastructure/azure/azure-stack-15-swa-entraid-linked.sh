#!/usr/bin/env bash
#
# azure-stack-15-swa-entraid-linked.sh - Deploy Stack 2: Public SWA + Entra ID + Linked Backend
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
#   │ - /api/* → SWA Proxy → Function     │
#   │ - Custom domain + azurestaticapps   │
#   └──────────────┬──────────────────────┘
#                  │ Linked backend
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Linked to SWA as managed backend  │
#   │ - Accessible via both custom domains│
#   │ - No auth on Function (SWA handles) │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (linked to SWA, no Function-level auth)
#   - Authentication: Entra ID on SWA (protects frontend + API via proxy)
#   - Security: Platform-level auth, HttpOnly cookies
#   - Use case: Enterprise apps, internal tools, RECOMMENDED setup
#   - Cost: ~$9/month (Standard tier SWA + Consumption)
#
# Key Benefits:
#   - Same-origin API calls (no CORS issues)
#   - HttpOnly cookies (secure, XSS protection)
#   - API accessed via SWA proxy (Entra ID required)
#   - Multiple redirect URIs (azurestaticapps.net + custom domain)
#   - Simple setup, good balance
#
# Custom Domains:
#   - SWA: static-swa-entraid-linked.publiccloudexperiments.net
#   - Function: subnet-calc-fa-entraid-linked.publiccloudexperiments.net
#
# Redirect URIs (both required):
#   - https://<app>.azurestaticapps.net/.auth/login/aad/callback
#   - https://static-swa-entraid-linked.publiccloudexperiments.net/.auth/login/aad/callback
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" ./azure-stack-15-swa-entraid-linked.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID (existing: 370b8618-a252-442e-9941-c47a9f7da89e)
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   SWA_CUSTOM_DOMAIN    - SWA custom domain (default: static-swa-entraid-linked.publiccloudexperiments.net)
#   FUNC_CUSTOM_DOMAIN   - Function custom domain (default: subnet-calc-fa-entraid-linked.publiccloudexperiments.net)

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
readonly SWA_CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN:-static-swa-entraid-linked.publiccloudexperiments.net}"
readonly FUNC_CUSTOM_DOMAIN="${FUNC_CUSTOM_DOMAIN:-subnet-calc-fa-entraid-linked.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-linked}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-entraid-linked}"
readonly STATIC_WEB_APP_SKU="Standard"  # Required for Entra ID

# Validate required environment variables
if [[ -z "${AZURE_CLIENT_ID:-}" ]] || [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_error "AZURE_CLIENT_ID and AZURE_CLIENT_SECRET are required"
  log_error "Usage: AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=xxx $0"
  exit 1
fi

readonly AZURE_CLIENT_ID
readonly AZURE_CLIENT_SECRET

# Map region to SWA-compatible region
REQUESTED_LOCATION="${LOCATION:-uksouth}"
SWA_LOCATION=$(map_swa_region "${REQUESTED_LOCATION}")
readonly LOCATION="${SWA_LOCATION}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 2: Public SWA + Entra ID + Linked Backend"
log_info "RECOMMENDED SETUP"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID protected)"
log_info "  Backend:  Function App (linked, no Function auth)"
log_info "  Auth:     Entra ID on SWA (protects frontend + API)"
log_info "  Security: Platform-level, HttpOnly cookies"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption)"
log_info "  SWA Domain:  ${SWA_CUSTOM_DOMAIN}"
log_info "  Func Domain: ${FUNC_CUSTOM_DOMAIN}"
log_info "  Region:      ${LOCATION}"
log_info ""
log_info "Key benefits:"
log_info "  ✓ Enterprise-grade authentication"
log_info "  ✓ Same-origin API calls (no CORS)"
log_info "  ✓ Secure HttpOnly cookies"
log_info "  ✓ Multiple domain support"
log_info ""

# Check prerequisites
log_step "Checking prerequisites..."
command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }
command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
command -v npm &>/dev/null || { log_error "npm not found"; exit 1; }

az account show &>/dev/null || { log_error "Not logged in to Azure"; exit 1; }
log_info "Prerequisites OK"
echo ""

# Auto-detect or prompt for resource group
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  source "${SCRIPT_DIR}/lib/selection-utils.sh"
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found. Please select one:"
    RESOURCE_GROUP=$(select_resource_group)
  fi
fi

readonly RESOURCE_GROUP
export RESOURCE_GROUP
log_info "Using resource group: ${RESOURCE_GROUP}"
echo ""

# Step 1: Create Function App
log_step "Step 1/7: Creating Function App..."
echo ""

export FUNCTION_APP_NAME
export LOCATION

"${SCRIPT_DIR}/10-function-app.sh"

log_info "Configuring Function App settings (no auth - SWA handles it)..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=none \
    CORS_ORIGINS="https://${SWA_CUSTOM_DOMAIN}" \
  --output none

log_info "Function App configured"
echo ""

# Step 2: Deploy Function API
log_step "Step 2/7: Deploying Function API..."
echo ""

export DISABLE_AUTH=true  # No auth on Function (SWA handles it)

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed"
sleep 30
echo ""

# Step 3: Create Static Web App
log_step "Step 3/7: Creating Azure Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export STATIC_WEB_APP_SKU

"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 4: Link Function App to SWA
log_step "Step 4/7: Linking Function App to SWA..."
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

# Step 5: Update Entra ID App Registration
log_step "Step 5/7: Updating Entra ID app registration with redirect URIs..."
echo ""

log_info "Adding redirect URIs for both domains..."
log_info "  1. https://${SWA_URL}/.auth/login/aad/callback"
log_info "  2. https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"
echo ""

# Get current redirect URIs
CURRENT_REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris" -o json)

# Add new URIs
NEW_REDIRECT_URIS=$(echo "${CURRENT_REDIRECT_URIS}" | jq \
  --arg uri1 "https://${SWA_URL}/.auth/login/aad/callback" \
  --arg uri2 "https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback" \
  '. + [$uri1, $uri2] | unique')

az ad app update \
  --id "${AZURE_CLIENT_ID}" \
  --web-redirect-uris "${NEW_REDIRECT_URIS}" \
  --output none

# Add logout URI
az ad app update \
  --id "${AZURE_CLIENT_ID}" \
  --set web.logoutUrl="https://${SWA_CUSTOM_DOMAIN}/logged-out.html" \
  --output none

log_info "Entra ID app updated with redirect URIs"
echo ""

# Step 6: Configure Entra ID on SWA
log_step "Step 6/7: Configuring Entra ID authentication on SWA..."
echo ""

export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export AZURE_CLIENT_SECRET

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
echo ""

# Step 7: Deploy Frontend
log_step "Step 7/7: Deploying frontend..."
echo ""

FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"

[[ ! -d "node_modules" ]] && npm install

log_info "Building frontend with Entra ID auth..."
log_info "  API URL: (empty - use /api route via SWA proxy)"

VITE_AUTH_ENABLED=true \
VITE_API_URL="" \
npm run build

# Copy Entra ID builtin config
CONFIG_SOURCE="${SCRIPT_DIR}/staticwebapp-entraid-builtin.config.json"
if [[ -f "${CONFIG_SOURCE}" ]]; then
  log_info "Copying Entra ID builtin SWA config..."
  cp "${CONFIG_SOURCE}" dist/staticwebapp.config.json
else
  log_error "staticwebapp-entraid-builtin.config.json not found"
  exit 1
fi

DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

command -v swa &>/dev/null || npm install -g @azure/static-web-apps-cli

log_info "Deploying frontend to SWA..."
npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --api-location "" \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --no-use-keychain

log_info "Frontend deployed"
echo ""

# Step 8: Configure Custom Domains
log_step "Step 8/7: Configuring custom domains..."
echo ""

log_info "SWA Custom domain: ${SWA_CUSTOM_DOMAIN}"
log_info ""
log_warn "MANUAL STEP REQUIRED:"
log_warn "Create DNS CNAME record:"
log_warn "  ${SWA_CUSTOM_DOMAIN} → ${SWA_URL}"
log_warn ""
read -r -p "Press Enter after DNS record is created..."

export CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN}"
"${SCRIPT_DIR}/41-configure-custom-domain-swa.sh"

log_info "SWA custom domain configured"
echo ""

FUNC_DEFAULT_HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv)

log_info "Function App Custom domain: ${FUNC_CUSTOM_DOMAIN}"
log_info ""
log_warn "MANUAL STEP REQUIRED:"
log_warn "Create DNS CNAME record:"
log_warn "  ${FUNC_CUSTOM_DOMAIN} → ${FUNC_DEFAULT_HOSTNAME}"
log_warn ""
read -r -p "Press Enter after DNS record is created..."

log_info "Adding custom domain to Function App..."
az functionapp config hostname add \
  --webapp-name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${FUNC_CUSTOM_DOMAIN}"

log_info "Enabling HTTPS..."
az functionapp config ssl bind \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --certificate-thumbprint \
    "$(az functionapp config ssl upload \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --certificate-name "${FUNC_CUSTOM_DOMAIN}" \
      --query thumbprint -o tsv)" \
  --ssl-type SNI

log_info "Function App custom domain configured"
echo ""

# Summary
log_info "========================================="
log_info "Stack 2 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA Primary:  https://${SWA_CUSTOM_DOMAIN}"
log_info "  SWA Default:  https://${SWA_URL}"
log_info "  Function:     https://${FUNC_CUSTOM_DOMAIN}"
log_info ""
log_info "Authentication:"
log_info "  Type:         Entra ID (platform-level)"
log_info "  Login URL:    https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad"
log_info "  Logout URL:   https://${SWA_CUSTOM_DOMAIN}/logout"
log_info "  User Info:    https://${SWA_CUSTOM_DOMAIN}/.auth/me"
log_info ""
log_info "Test the deployment:"
log_info "  1. Visit https://${SWA_CUSTOM_DOMAIN}"
log_info "  2. Sign in with Entra ID credentials"
log_info "  3. Verify API calls work via /api/* proxy"
log_info "  4. Test logout flow"
log_info ""
log_info "Redirect URIs configured:"
log_info "  - https://${SWA_URL}/.auth/login/aad/callback"
log_info "  - https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "API Documentation:"
log_info "  https://${FUNC_CUSTOM_DOMAIN}/api/v1/docs"
log_info ""
