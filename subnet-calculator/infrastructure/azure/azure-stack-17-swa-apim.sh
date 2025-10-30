#!/usr/bin/env bash
#
# Stack 17: Static Web App + APIM (External VNet Mode) + Function App
#
# Architecture:
#   Internet → AppGW (HTTPS) → SWA (private endpoint)
#                              ↓ az staticwebapp backends link
#                              APIM (VNet external mode - public gateway)
#                              ↓ internal VNet routing
#                              Function (private endpoint)
#
# Key Features:
#   - APIM in External VNet mode (public gateway, private backends)
#   - SWA→APIM linking enables automatic product/subscription/JWT config
#   - Reuses AppGW from Stack 16 (adds new HTTPS listener)
#   - Reuses Function App with private endpoint from Stack 16
#   - All Azure "magic" automation for SWA→APIM integration
#
# Prerequisites:
#   - Stack 16 must be deployed (provides: VNet, AppGW, Function with PE, Key Vault)
#   - Cloudflare API token for DNS validation
#   - Custom domain: static-swa-apim.publiccloudexperiments.net
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   CUSTOM_DOMAIN="static-swa-apim.publiccloudexperiments.net" \
#   ./azure-stack-17-swa-apim.sh

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

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
readonly STATIC_WEB_APP_NAME="swa-subnet-calc-apim"
readonly APIM_NAME_PREFIX="apim-subnet-calc"
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-static-swa-apim.publiccloudexperiments.net}"

# Infrastructure from Stack 16 (reused)
readonly VNET_NAME="vnet-subnet-calc-private"
readonly APPGW_NAME="agw-swa-subnet-calc-private-endpoint"

log_info ""
log_info "==========================================="
log_info "Stack 17: SWA + APIM (External) + Function"
log_info "==========================================="
log_info ""
log_info "Custom Domain: ${CUSTOM_DOMAIN}"
log_info "SWA Name:      ${STATIC_WEB_APP_NAME}"
log_info "APIM Prefix:   ${APIM_NAME_PREFIX}"
log_info ""
log_info "Reused from Stack 16:"
log_info "  - VNet:      ${VNET_NAME}"
log_info "  - AppGW:     ${APPGW_NAME}"
log_info "  - Function:  (auto-detected)"
log_info "  - Key Vault: (auto-detected)"
log_info ""

# Validate prerequisites
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

# Verify Stack 16 infrastructure exists
log_step "Verifying Stack 16 infrastructure..."

# Check VNet
if ! az network vnet show --name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "VNet '${VNET_NAME}' not found. Deploy Stack 16 first"
  exit 1
fi

# Check AppGW
if ! az network application-gateway show --name "${APPGW_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Application Gateway '${APPGW_NAME}' not found. Deploy Stack 16 first"
  exit 1
fi

# Check for Function App with private endpoint
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?contains(name, 'func-subnet-calc')].name | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${FUNCTION_APP_NAME}" ]]; then
  log_error "No Function App found. Deploy Stack 16 first"
  exit 1
fi

# Check for Key Vault
KEY_VAULT_NAME=$(az keyvault list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")

if [[ -z "${KEY_VAULT_NAME}" ]]; then
  log_error "No Key Vault found. Deploy Stack 16 first"
  exit 1
fi

log_info "✓ Stack 16 infrastructure verified"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Key Vault:    ${KEY_VAULT_NAME}"
log_info ""

# Export for child scripts
export RESOURCE_GROUP
export VNET_NAME
export FUNCTION_APP_NAME
export KEY_VAULT_NAME
export STATIC_WEB_APP_NAME
export CUSTOM_DOMAIN
export APPGW_NAME

# Get location
LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
export LOCATION

log_info "Starting Stack 17 deployment..."
log_info ""

# Step 1: Create APIM with VNet External mode (~45 min)
log_step "Step 1/9: Create APIM instance (VNet External mode)"
log_warn "⏱️  This will take approximately 45-55 minutes"
log_info ""

export APIM_VNET_MODE="External"
export APIM_SKU="Developer"

"${SCRIPT_DIR}/43-create-apim-vnet.sh"

# Get APIM name (created or existing)
APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
export APIM_NAME

log_info ""
log_info "✓ APIM instance ready: ${APIM_NAME}"
log_info ""

# Step 2: Setup App Registration for Entra ID
log_step "Step 2/9: Setup App Registration"
"${SCRIPT_DIR}/52-setup-app-registration.sh"

log_info ""
log_info "✓ App Registration ready"
log_info ""

# Step 3: Create Static Web App
log_step "Step 3/9: Create Static Web App"

if az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Static Web App already exists: ${STATIC_WEB_APP_NAME}"
else
  log_info "Creating Static Web App: ${STATIC_WEB_APP_NAME}"
  az staticwebapp create \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard \
    --output none

  log_info "✓ Static Web App created"
fi

log_info ""

# Step 4: Create private endpoint for SWA
log_step "Step 4/9: Create private endpoint for SWA"
"${SCRIPT_DIR}/48-create-private-endpoint-swa.sh"

log_info ""
log_info "✓ SWA private endpoint ready"
log_info ""

# Step 5: Configure APIM backend (import Function OpenAPI)
log_step "Step 5/9: Configure APIM backend"

# Get Function URL
FUNCTION_URL=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

export FUNCTION_URL="https://${FUNCTION_URL}"

"${SCRIPT_DIR}/31-apim-backend.sh"

log_info ""
log_info "✓ APIM backend configured"
log_info ""

# Step 6: Apply APIM policies (subscription mode)
log_step "Step 6/9: Apply APIM policies"

export AUTH_MODE="subscription"
"${SCRIPT_DIR}/32-apim-policies.sh"

log_info ""
log_info "✓ APIM policies applied"
log_info ""

# Step 7: Link SWA to APIM
log_step "Step 7/9: Link SWA to APIM backend"
"${SCRIPT_DIR}/44-link-swa-to-apim.sh"

log_info ""
log_info "✓ SWA linked to APIM"
log_info ""

# Step 8: Deploy frontend code to SWA
log_step "Step 8/9: Deploy frontend code"

SWA_DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.apiKey" -o tsv)

log_info "Frontend deployment token retrieved"
log_warn "TODO: Deploy frontend code using SWA CLI or GitHub Actions"
log_warn "Deployment token: ${SWA_DEPLOYMENT_TOKEN}"
log_info ""

# Step 9: Add HTTPS listener to AppGW
log_step "Step 9/9: Add HTTPS listener to Application Gateway"

# Get SWA private FQDN
SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostname" -o tsv)

# Construct private FQDN
if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
  SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
  SWA_PRIVATE_FQDN="${SWA_HOSTNAME/.${SWA_REGION_NUMBER}.azurestaticapps.net/.privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net}"
else
  log_error "Could not determine SWA region number"
  exit 1
fi

export LISTENER_NAME="swa-apim-listener"
export BACKEND_FQDN="${SWA_PRIVATE_FQDN}"

"${SCRIPT_DIR}/54-add-https-listener-named.sh"

log_info ""
log_info "✓ HTTPS listener configured"
log_info ""

# Get AppGW public IP
APPGW_PUBLIC_IP=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "frontendIPConfigurations[0].publicIPAddress.id" -o tsv | \
  xargs -I {} az network public-ip show --ids {} --query ipAddress -o tsv)

# Summary
log_info ""
log_info "========================================="
log_info "✓ Stack 17 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Internet → AppGW → SWA (private) → APIM (external) → Function (private)"
log_info ""
log_info "Resources Created:"
log_info "  Static Web App:   ${STATIC_WEB_APP_NAME}"
log_info "  APIM Instance:    ${APIM_NAME} (VNet External mode)"
log_info "  AppGW Listener:   ${LISTENER_NAME}"
log_info "  Custom Domain:    ${CUSTOM_DOMAIN}"
log_info ""
log_info "Reused from Stack 16:"
log_info "  VNet:             ${VNET_NAME}"
log_info "  Application GW:   ${APPGW_NAME}"
log_info "  Function App:     ${FUNCTION_APP_NAME}"
log_info "  Key Vault:        ${KEY_VAULT_NAME}"
log_info ""
log_info "URLs:"
log_info "  AppGW Public IP:  ${APPGW_PUBLIC_IP}"
log_info "  SWA Default:      https://${SWA_HOSTNAME}"
log_info "  Custom Domain:    https://${CUSTOM_DOMAIN} (after DNS config)"
log_info ""
log_info "APIM URLs:"
log_info "  Gateway:          $(az apim show --name "${APIM_NAME}" --resource-group "${RESOURCE_GROUP}" --query gatewayUrl -o tsv)"
log_info "  Portal:           $(az apim show --name "${APIM_NAME}" --resource-group "${RESOURCE_GROUP}" --query developerPortalUrl -o tsv 2>/dev/null || echo "N/A")"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure DNS A record:"
log_info "     ${CUSTOM_DOMAIN} → ${APPGW_PUBLIC_IP}"
log_info ""
log_info "  2. Deploy frontend code to SWA"
log_info ""
log_info "  3. Test API access through SWA:"
log_info "     curl https://${CUSTOM_DOMAIN}/api/v1/health"
log_info ""
log_info "SWA→APIM Integration:"
log_info "  ✓ Automatic APIM product created"
log_info "  ✓ Subscription key configured"
log_info "  ✓ JWT validation enabled"
log_info "  ✓ /api/* requests proxied to APIM"
log_info ""
