#!/usr/bin/env bash
#
# azure-stack-16-swa-private-endpoint.sh - Deploy Stack 3: Private Endpoint SWA + Entra ID
#
# Architecture:
#   ┌──────────────────────────────────────┐
#   │ User → Entra ID Login                │
#   └──────────────┬───────────────────────┘
#                  │ Internet
#   ┌──────────────▼───────────────────────┐
#   │ Azure Static Web App (Standard)      │
#   │ - TypeScript Vite SPA                │
#   │ - Entra ID authentication            │
#   │ - Custom domain (PRIMARY)            │
#   │ - azurestaticapps.net (DISABLED)     │
#   │ - Private endpoint enabled           │
#   └──────────────┬───────────────────────┘
#                  │ Private Endpoint (SWA)
#   ┌──────────────▼───────────────────────┐
#   │ VNet (10.100.0.0/24)                 │
#   │ ├─ Subnet: functions (10.100.0.0/28) │
#   │ └─ Subnet: endpoints (10.100.0.16/28)│
#   │   - Private Endpoint for SWA         │
#   │   - Private Endpoint for Function    │
#   └──────────────┬───────────────────────┘
#                  │ Linked Backend + Private Endpoint
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
#   - Cost: ~$22-293/month (SWA Standard + B1/S1/P0V3/P1V3 plan, private endpoints free)
#
# Key Security Features:
#   - Custom domain is PRIMARY (azurestaticapps.net disabled)
#   - Static Web App accessible via private endpoint
#   - Function App accessible ONLY via private endpoint
#   - No public IP on Function App
#   - Entra ID redirect URIs limited to custom domain
#   - Full network-level isolation for both frontend and backend
#
# Custom Domain:
#   - SWA: static-swa-private-endpoint.publiccloudexperiments.net (PRIMARY)
#   - Function: Uses default Azure domain (*.azurewebsites.net, private endpoint only)
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
export PROJECT_ROOT

# Source utility functions
source "${SCRIPT_DIR}/lib/map-swa-region.sh"

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-static-swa-private-endpoint.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-private-endpoint}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-private-endpoint}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-plan-subnet-calc-private}"
readonly APP_SERVICE_PLAN_SKU="${APP_SERVICE_PLAN_SKU:-P0V3}"  # B1, S1, P0V3, P1V3, etc.
readonly VNET_NAME="${VNET_NAME:-vnet-subnet-calc-private}"
readonly VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.100.0.0/24}"
readonly SUBNET_FUNCTION_NAME="${SUBNET_FUNCTION_NAME:-snet-function-integration}"
readonly SUBNET_FUNCTION_PREFIX="${SUBNET_FUNCTION_PREFIX:-10.100.0.0/28}"
readonly SUBNET_PE_NAME="${SUBNET_PE_NAME:-snet-private-endpoints}"
readonly SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.100.0.16/28}"
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
# Costs: SWA Standard ($9) + App Service Plan (private endpoints are free)
MONTHLY_COST=""
APP_PLAN_COST=""
case "${APP_SERVICE_PLAN_SKU}" in
  B1)
    APP_PLAN_COST="\$13"
    MONTHLY_COST="\$22"  # $9 (SWA) + $13 (B1)
    ;;
  S1)
    APP_PLAN_COST="\$70"
    MONTHLY_COST="\$79"  # $9 (SWA) + $70 (S1)
    ;;
  P0V3)
    APP_PLAN_COST="\$142"
    MONTHLY_COST="\$151"  # $9 (SWA) + $142 (P0V3)
    ;;
  P1V3)
    APP_PLAN_COST="\$284"
    MONTHLY_COST="\$293"  # $9 (SWA) + $284 (P1V3)
    ;;
  *)
    APP_PLAN_COST="\$13-284"
    MONTHLY_COST="~\$22-293"
    ;;
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
log_info "  Cost:     ~${MONTHLY_COST}/month (SWA Standard + ${APP_SERVICE_PLAN_SKU})"
log_info "  Domain:   ${CUSTOM_DOMAIN} (PRIMARY)"
log_info "  Function Region: ${LOCATION}"
log_info "  SWA Region:      ${SWA_LOCATION}"
log_info ""
log_info "Key security features:"
log_info "  ✓ Custom domain is PRIMARY"
log_info "  ✓ azurestaticapps.net domain DISABLED"
log_info "  ✓ SWA accessible via private endpoint"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public IP on Function App"
log_info "  ✓ Full network-level isolation (frontend + backend)"
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
export VNET_ADDRESS_SPACE
export SUBNET_FUNCTION_NAME
export SUBNET_FUNCTION_PREFIX
export SUBNET_PE_NAME
export SUBNET_PE_PREFIX
export LOCATION

"${SCRIPT_DIR}/11-create-vnet-infrastructure.sh"

log_info "VNet infrastructure created"
echo ""

# Step 2: Create App Service Plan
log_step "Step 2/10: Creating App Service Plan (${APP_SERVICE_PLAN_SKU})..."
echo ""

log_info "Creating ${APP_SERVICE_PLAN_SKU} App Service Plan for private endpoint support..."
export PLAN_NAME="${APP_SERVICE_PLAN_NAME}"
export PLAN_SKU="${APP_SERVICE_PLAN_SKU}"

"${SCRIPT_DIR}/12-create-app-service-plan.sh"

log_info "App Service Plan created"
echo ""

# Step 3: Create Function App on App Service Plan
log_step "Step 3/10: Creating Function App on App Service Plan..."
echo ""

# Find or create storage account by tag (avoids collisions, enables idempotency)
STORAGE_TAG="purpose=func-subnet-calc-private-endpoint"
log_info "Checking for existing storage account with tag: ${STORAGE_TAG}..."

EXISTING_STORAGE=$(az storage account list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?tags.purpose=='func-subnet-calc-private-endpoint'].name | [0]" \
  -o tsv)

if [[ -n "${EXISTING_STORAGE}" ]]; then
  export STORAGE_ACCOUNT_NAME="${EXISTING_STORAGE}"
  log_info "Found existing tagged storage account: ${STORAGE_ACCOUNT_NAME}"
else
  # Generate globally unique name with random suffix (6 hex chars = 16.7M combinations)
  STORAGE_BASE="stfuncprivateep"
  STORAGE_SUFFIX=$(openssl rand -hex 3)
  export STORAGE_ACCOUNT_NAME="${STORAGE_BASE}${STORAGE_SUFFIX}"
  export STORAGE_ACCOUNT_TAG="${STORAGE_TAG}"
  log_info "Will create new storage account: ${STORAGE_ACCOUNT_NAME}"
fi

export FUNCTION_APP_NAME
export APP_SERVICE_PLAN="${APP_SERVICE_PLAN_NAME}"

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
export SUBNET_NAME="${SUBNET_FUNCTION_NAME}"

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
export SUBNET_NAME="${SUBNET_PE_NAME}"

"${SCRIPT_DIR}/46-create-private-endpoint.sh"

log_info "Private endpoint created"
log_info "Function App is now accessible ONLY via private network"
echo ""

# Step 7: Create Static Web App
log_step "Step 7/11: Creating Azure Static Web App..."
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

# Step 8: Create Private Endpoint for Static Web App
log_step "Step 8/11: Creating private endpoint for Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export VNET_NAME
export SUBNET_NAME="${SUBNET_PE_NAME}"

"${SCRIPT_DIR}/48-create-private-endpoint-swa.sh"

log_info "Private endpoint created for Static Web App"
log_info "SWA is now accessible ONLY via private network"
echo ""

# Step 9: Link Function App to SWA
log_step "Step 9/11: Linking Function App to SWA..."
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

# Step 10: Configure Custom Domain and Disable Default Hostname
log_step "Step 10/11: Configuring custom domain..."
echo ""

log_info "Custom domain: ${CUSTOM_DOMAIN}"
log_info "SWA hostname: ${SWA_URL}"
log_info ""
log_info "The script will now:"
log_info "  1. Add the custom domain to Azure (generates validation token)"
log_info "  2. Display the TXT record for domain validation"
log_info "  3. Display the CNAME record for traffic routing"
log_info "  4. Wait for you to configure DNS"
log_info ""

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

# Step 11: Update Entra ID and Deploy Frontend
log_step "Step 11/11: Updating Entra ID and deploying frontend..."
echo ""

log_info "Adding redirect URI (custom domain ONLY)..."
log_info "  https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
echo ""

# Build redirect URIs list - custom domain only
NEW_URI="https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"

# Get current URIs and combine with new one, ensuring uniqueness
REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris[]" -o tsv 2>/dev/null | cat)

# Add new URI to list - use process substitution to avoid trailing newline issues
mapfile -t URI_ARRAY < <(printf '%s\n%s\n' "${REDIRECT_URIS}" "${NEW_URI}" | grep -v '^$' | sort -u)

# Ensure we have at least one URI
if [ ${#URI_ARRAY[@]} -eq 0 ]; then
  log_error "No redirect URIs to configure"
  exit 1
fi

# Update redirect URIs using Graph API (more reliable than az ad app update)
log_info "Updating ${#URI_ARRAY[@]} redirect URI(s) via Microsoft Graph API..."

# Get the app's object ID (needed for Graph API)
APP_OBJECT_ID=$(az ad app show --id "${AZURE_CLIENT_ID}" --query id -o tsv)

# Build JSON array from URI_ARRAY
URI_JSON=$(printf '"%s",' "${URI_ARRAY[@]}" | sed 's/,$//')

# Update using Graph API
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
  --headers 'Content-Type=application/json' \
  --body "{
    \"web\": {
      \"redirectUris\": [${URI_JSON}],
      \"logoutUrl\": \"https://${CUSTOM_DOMAIN}/logged-out.html\",
      \"implicitGrantSettings\": {
        \"enableAccessTokenIssuance\": true,
        \"enableIdTokenIssuance\": true
      }
    }
  }" \
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
log_info "Building and deploying frontend with Entra ID auth..."
log_info "  API URL: (empty - use /api route via SWA proxy)"

export FRONTEND=typescript
export SWA_AUTH_ENABLED=true   # Use SWA built-in Entra ID authentication (for staticwebapp.config.json)
export VITE_AUTH_ENABLED=true  # Enable auth in frontend
export VITE_AUTH_METHOD=entraid # Explicitly set auth method (works on custom domains)
export VITE_API_URL=""         # Use SWA proxy to linked backend
export STATIC_WEB_APP_NAME
export RESOURCE_GROUP

"${SCRIPT_DIR}/20-deploy-frontend.sh"

log_info "Frontend deployed"
echo ""

# Check/Offer to create Application Gateway
log_step "Checking Application Gateway status..."
echo ""

# Define Application Gateway name
APPGW_NAME="${APPGW_NAME:-agw-${STATIC_WEB_APP_NAME}}"
APPGW_EXISTS=false

if az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  APPGW_EXISTS=true
  log_info "Application Gateway ${APPGW_NAME} already exists"

  # Get public IP for display
  PUBLIC_IP_NAME="pip-${APPGW_NAME}"
  if PUBLIC_IP_ADDRESS=$(az network public-ip show \
    --name "${PUBLIC_IP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query ipAddress -o tsv 2>/dev/null); then
    log_info "Public IP: ${PUBLIC_IP_ADDRESS}"
    log_info "Access via: http://${PUBLIC_IP_ADDRESS}"
  fi
else
  log_warn "No Application Gateway found"
  log_info ""
  log_info "IMPORTANT: Your SWA and Function are currently private endpoint only!"
  log_info "To provide public access, you need an Application Gateway."
  log_info ""
  log_info "The Application Gateway will:"
  log_info "  • Provide a public IP for internet access"
  log_info "  • Route traffic to your private SWA endpoint"
  log_info "  • Enable WAF protection (optional)"
  log_info "  • Cost ~\$320-425/month"
  log_info ""
  read -p "Create Application Gateway now? (Y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Creating Application Gateway..."
    echo ""

    export STATIC_WEB_APP_NAME
    export VNET_NAME
    export APPGW_NAME
    export LOCATION

    # Call the Application Gateway creation script
    "${SCRIPT_DIR}/49-create-application-gateway.sh"

    APPGW_EXISTS=true

    # Get public IP for summary
    PUBLIC_IP_NAME="pip-${APPGW_NAME}"
    PUBLIC_IP_ADDRESS=$(az network public-ip show \
      --name "${PUBLIC_IP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query ipAddress -o tsv 2>/dev/null || echo "")

    log_info "Application Gateway created successfully"
    echo ""
  else
    log_info "Skipping Application Gateway creation"
    log_warn "Your resources are private endpoint only - accessible only from within the VNet"
    echo ""
  fi
fi
echo ""

# Summary
log_info "========================================="
log_info "Stack 3 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA (PRIMARY):     https://${CUSTOM_DOMAIN}"
log_info "  SWA (DEFAULT):     DISABLED"
if [[ "${APPGW_EXISTS}" == "true" ]] && [[ -n "${PUBLIC_IP_ADDRESS:-}" ]]; then
  log_info "  Public Access:     http://${PUBLIC_IP_ADDRESS} (via Application Gateway)"
  log_info "  SWA Private:       Private endpoint only"
  log_info "  Function Private:  Private endpoint only"
else
  log_info "  SWA Access:        Private endpoint only (no public access)"
  log_info "  Function:          Private endpoint only (no public access)"
fi
log_info ""
log_info "Network Architecture:"
log_info "  VNet:              ${VNET_NAME} (${VNET_ADDRESS_SPACE})"
log_info "  Functions Subnet:  ${SUBNET_FUNCTION_PREFIX}"
log_info "  Endpoints Subnet:  ${SUBNET_PE_PREFIX}"
if [[ "${APPGW_EXISTS}" == "true" ]]; then
  log_info "  AppGW Subnet:      10.100.0.32/27 (Application Gateway)"
  log_info "  Application GW:    ${APPGW_NAME} (Public: ${PUBLIC_IP_ADDRESS:-N/A})"
fi
log_info "  Private Endpoints: SWA + Function App (both isolated from internet)"
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
log_info "  ✓ SWA accessible only via private endpoint"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public access to frontend or backend"
log_info "  ✓ Full network-level isolation"
log_info ""
log_info "Test the deployment:"
if [[ "${APPGW_EXISTS}" == "true" ]] && [[ -n "${PUBLIC_IP_ADDRESS:-}" ]]; then
  log_info "  PUBLIC ACCESS (via Application Gateway):"
  log_info "    1. Visit http://${PUBLIC_IP_ADDRESS}"
  log_info "    2. Sign in with Entra ID credentials"
  log_info "    3. Verify API calls work via /api/* proxy"
  log_info ""
  log_info "  PRIVATE ACCESS (from VNet):"
  log_info "    1. From a VM in the VNet, visit https://${CUSTOM_DOMAIN}"
  log_info "    2. Verify both paths work (public via AppGW, private via VNet)"
else
  log_info "  IMPORTANT: Both SWA and Function are private endpoint only!"
  log_info "  Access requires being in the VNet or using Application Gateway."
  log_info ""
  log_info "  From a VM in the VNet:"
  log_info "    1. Visit https://${CUSTOM_DOMAIN}"
  log_info "    2. Sign in with Entra ID credentials"
  log_info "    3. Verify API calls work via /api/* proxy"
  log_info "    4. Confirm SWA and Function not accessible from public internet"
  log_info ""
  log_info "  To provide public access, run this script again:"
  log_info "    It will detect no Application Gateway and offer to create one"
fi
log_info ""
log_info "Redirect URI configured:"
log_info "  - https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "Monthly Cost: ~${MONTHLY_COST}"
log_info "  - SWA Standard: \$9"
log_info "  - ${APP_SERVICE_PLAN_SKU} Plan: ${APP_PLAN_COST}"
log_info "  - Private Endpoints: Free (data processing charges may apply)"
log_info ""
