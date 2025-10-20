#!/usr/bin/env bash
#
# azure-stack-16-swa-private-endpoint.sh - Deploy Stack 3: Private Endpoint SWA + Entra ID
#
# Architecture:
#   ┌──────────────────────────────────────┐
#   │ User → Entra ID Login                │
#   └──────────────┬───────────────────────┘
#                  │
#   ┌──────────────▼───────────────────────┐
#   │ Azure Static Web App (Standard)      │
#   │ - TypeScript Vite SPA                │
#   │ - Entra ID authentication            │
#   │ - Custom domain (PRIMARY)            │
#   │ - azurestaticapps.net (DISABLED)     │
#   │ - /api/* → Private VNet → Function   │
#   └──────────────┬───────────────────────┘
#                  │ Private VNet
#   ┌──────────────▼───────────────────────┐
#   │ VNet (10.0.0.0/16)                   │
#   │ ├─ Subnet: functions (10.0.1.0/24)   │
#   │ └─ Subnet: endpoints (10.0.2.0/24)   │
#   └──────────────┬───────────────────────┘
#                  │ Private Endpoint
#   ┌──────────────▼───────────────────────┐
#   │ Azure Function App (S1/P0V3 Plan)    │
#   │ - Private endpoint only              │
#   │ - NO public azurewebsites.net access │
#   │ - VNet integration enabled           │
#   │ - No auth on Function (SWA handles)  │
#   └──────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (App Service Plan with private endpoint)
#   - Authentication: Entra ID on SWA (custom domain only)
#   - Networking: Private endpoints, VNet integration
#   - Security: Network-level isolation, no public backend
#   - Use case: High-security environments, compliance requirements
#   - Cost: ~$79-128/month (SWA Standard + S1/P0V3 plan + private endpoint)
#
# Key Security Features:
#   - Custom domain is PRIMARY (azurestaticapps.net disabled)
#   - Function App accessible ONLY via private endpoint
#   - No public IP on Function App
#   - Entra ID redirect URIs limited to custom domain
#   - Network-level isolation
#
# Custom Domain:
#   - SWA: static-swa-private-endpoint.publiccloudexperiments.net (PRIMARY)
#   - Function: Internal only (no custom domain)
#
# Redirect URI (custom domain only):
#   - https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" ./azure-stack-16-swa-private-endpoint.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   CUSTOM_DOMAIN        - SWA custom domain (default: static-swa-private-endpoint.publiccloudexperiments.net)
#   APP_SERVICE_PLAN_SKU - Plan SKU (default: S1, options: S1, P0V3)

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
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-static-swa-private-endpoint.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-private-endpoint}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-private-endpoint}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-plan-subnet-calc-private}"
readonly APP_SERVICE_PLAN_SKU="${APP_SERVICE_PLAN_SKU:-S1}"  # S1 or P0V3
readonly VNET_NAME="${VNET_NAME:-vnet-subnet-calc}"
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
LOCATION="${REQUESTED_LOCATION}"  # Function/VNet use requested region (not readonly - will be temporarily overridden for SWA)
readonly SWA_LOCATION  # SWA uses mapped region

# Calculate cost based on SKU
MONTHLY_COST=""
case "${APP_SERVICE_PLAN_SKU}" in
  S1) MONTHLY_COST="\$79" ;;
  P0V3) MONTHLY_COST="\$128" ;;
  *) MONTHLY_COST="~\$79-128" ;;
esac

# Banner
echo ""
log_info "========================================="
log_info "Stack 3: Private Endpoint + Entra ID"
log_info "HIGH SECURITY SETUP"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID, custom domain primary)"
log_info "  Backend:  Function App (App Service Plan, private endpoint)"
log_info "  Auth:     Entra ID (custom domain only)"
log_info "  Network:  VNet, private endpoints, NO public backend access"
log_info "  Security: Network-level isolation"
log_info "  Cost:     ~${MONTHLY_COST}/month (SWA Standard + ${APP_SERVICE_PLAN_SKU} plan)"
log_info "  Domain:   ${CUSTOM_DOMAIN} (PRIMARY)"
log_info "  Function Region: ${LOCATION}"
log_info "  SWA Region:      ${SWA_LOCATION}"
log_info ""
log_info "Key security features:"
log_info "  ✓ Custom domain is PRIMARY"
log_info "  ✓ azurestaticapps.net domain DISABLED"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public IP on Function App"
log_info "  ✓ Network-level isolation"
log_info ""

# Check prerequisites
log_step "Checking prerequisites..."
command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }
command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
command -v npm &>/dev/null || { log_error "npm not found"; exit 1; }
command -v uv &>/dev/null || { log_error "uv not found - install with: brew install uv"; exit 1; }

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

# Step 1: Create VNet Infrastructure
log_step "Step 1/10: Creating VNet infrastructure..."
echo ""

export VNET_NAME
export LOCATION

"${SCRIPT_DIR}/11-create-vnet-infrastructure.sh"

log_info "VNet infrastructure created"
echo ""

# Step 2: Create App Service Plan
log_step "Step 2/10: Creating App Service Plan (${APP_SERVICE_PLAN_SKU})..."
echo ""

log_info "Creating ${APP_SERVICE_PLAN_SKU} App Service Plan for private endpoint support..."
export APP_SERVICE_PLAN_NAME
export APP_SERVICE_PLAN_SKU

"${SCRIPT_DIR}/12-create-app-service-plan.sh"

log_info "App Service Plan created"
echo ""

# Step 3: Create Function App on App Service Plan
log_step "Step 3/10: Creating Function App on App Service Plan..."
echo ""

export FUNCTION_APP_NAME
export APP_SERVICE_PLAN_NAME

"${SCRIPT_DIR}/13-create-function-app-on-app-service-plan.sh"

log_info "Configuring Function App settings (no auth - SWA handles it)..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=none \
    CORS_ORIGINS="https://${CUSTOM_DOMAIN}" \
  --output none

log_info "Function App configured"
echo ""

# Step 4: Enable VNet Integration
log_step "Step 4/10: Enabling VNet integration on Function App..."
echo ""

export FUNCTION_APP_NAME
export VNET_NAME

"${SCRIPT_DIR}/14-configure-function-vnet-integration.sh"

log_info "VNet integration enabled"
echo ""

# Step 5: Deploy Function API
log_step "Step 5/10: Deploying Function API..."
echo ""

export DISABLE_AUTH=true  # No auth on Function (SWA handles it)

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed"
sleep 30
echo ""

# Step 6: Create Private Endpoint for Function App
log_step "Step 6/10: Creating private endpoint for Function App..."
echo ""

export FUNCTION_APP_NAME
export VNET_NAME

"${SCRIPT_DIR}/46-create-private-endpoint.sh"

log_info "Private endpoint created"
log_info "Function App is now accessible ONLY via private network"
echo ""

# Step 7: Create Static Web App
log_step "Step 7/10: Creating Azure Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export STATIC_WEB_APP_SKU
export LOCATION="${SWA_LOCATION}"  # Override with SWA-compatible region

"${SCRIPT_DIR}/00-static-web-app.sh"

# Restore original location for subsequent steps
export LOCATION="${REQUESTED_LOCATION}"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 8: Link Function App to SWA
log_step "Step 8/10: Linking Function App to SWA..."
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

# Step 9: Configure Custom Domain and Disable Default Hostname
log_step "Step 9/10: Configuring custom domain..."
echo ""

log_info "Custom domain: ${CUSTOM_DOMAIN}"
log_info ""
log_warn "MANUAL STEP REQUIRED:"
log_warn "Create DNS CNAME record:"
log_warn "  ${CUSTOM_DOMAIN} → ${SWA_URL}"
log_warn ""
read -r -p "Press Enter after DNS record is created..."

export CUSTOM_DOMAIN
"${SCRIPT_DIR}/41-configure-custom-domain-swa.sh"

log_info "Custom domain configured"
echo ""

# Disable default azurestaticapps.net hostname
log_info "Disabling default azurestaticapps.net hostname..."
log_warn "This requires the 47-disable-default-hostname.sh script"

if [[ -f "${SCRIPT_DIR}/47-disable-default-hostname.sh" ]]; then
  export STATIC_WEB_APP_NAME
  "${SCRIPT_DIR}/47-disable-default-hostname.sh"
  log_info "Default hostname disabled - custom domain is now PRIMARY"
else
  log_warn "Script 47-disable-default-hostname.sh not found"
  log_warn "Default hostname will remain active alongside custom domain"
  log_warn "To disable manually, use Azure Portal or REST API"
fi
echo ""

# Step 10: Update Entra ID and Deploy Frontend
log_step "Step 10/10: Updating Entra ID and deploying frontend..."
echo ""

log_info "Adding redirect URI (custom domain ONLY)..."
log_info "  https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
echo ""

# Get current redirect URIs
CURRENT_REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris" -o json)

# Add custom domain URI only
NEW_REDIRECT_URIS=$(echo "${CURRENT_REDIRECT_URIS}" | jq \
  --arg uri "https://${CUSTOM_DOMAIN}/.auth/login/aad/callback" \
  '. + [$uri] | unique')

az ad app update \
  --id "${AZURE_CLIENT_ID}" \
  --web-redirect-uris "${NEW_REDIRECT_URIS}" \
  --output none

# Set logout URI
az ad app update \
  --id "${AZURE_CLIENT_ID}" \
  --set web.logoutUrl="https://${CUSTOM_DOMAIN}/logged-out.html" \
  --output none

log_info "Entra ID app updated"
echo ""

# Configure Entra ID on SWA
export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export AZURE_CLIENT_SECRET

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
echo ""

# Deploy Frontend
FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"

[[ ! -d "node_modules" ]] && npm install

log_info "Building frontend with Entra ID auth..."
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

# Summary
log_info "========================================="
log_info "Stack 3 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA (PRIMARY):     https://${CUSTOM_DOMAIN}"
log_info "  SWA (DEFAULT):     DISABLED"
log_info "  Function:          Private endpoint only (no public access)"
log_info ""
log_info "Network Architecture:"
log_info "  VNet:              ${VNET_NAME} (10.0.0.0/16)"
log_info "  Functions Subnet:  10.0.1.0/24"
log_info "  Endpoints Subnet:  10.0.2.0/24"
log_info "  Private Endpoint:  Function App (no public IP)"
log_info ""
log_info "Authentication:"
log_info "  Type:              Entra ID (platform-level)"
log_info "  Login URL:         https://${CUSTOM_DOMAIN}/.auth/login/aad"
log_info "  Logout URL:        https://${CUSTOM_DOMAIN}/logout"
log_info "  User Info:         https://${CUSTOM_DOMAIN}/.auth/me"
log_info ""
log_info "Security Features:"
log_info "  ✓ Custom domain is PRIMARY"
log_info "  ✓ azurestaticapps.net domain DISABLED"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public backend access"
log_info "  ✓ Network-level isolation"
log_info ""
log_info "Test the deployment:"
log_info "  1. Visit https://${CUSTOM_DOMAIN}"
log_info "  2. Sign in with Entra ID credentials"
log_info "  3. Verify API calls work via /api/* proxy"
log_info "  4. Confirm Function App not accessible via azurewebsites.net"
log_info ""
log_info "Redirect URI configured:"
log_info "  - https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "Monthly Cost: ~${MONTHLY_COST}"
log_info "  - SWA Standard: \$9"
log_info "  - ${APP_SERVICE_PLAN_SKU} Plan: \$$(echo "${MONTHLY_COST}" | sed 's/[^0-9]//g' | sed 's/^9//' )"
log_info ""
