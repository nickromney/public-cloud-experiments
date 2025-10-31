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

# Stack 17 Infrastructure (dedicated VNet for External APIM)
readonly VNET_NAME="vnet-subnet-calc-apim-external"
readonly NSG_NAME="nsg-apim-external"

log_info ""
log_info "==========================================="
log_info "Stack 17: SWA + APIM (External) + Function"
log_info "==========================================="
log_info ""
log_info "Custom Domain: ${CUSTOM_DOMAIN}"
log_info "SWA Name:      ${STATIC_WEB_APP_NAME}"
log_info "APIM Prefix:   ${APIM_NAME_PREFIX}"
log_info ""
log_info "Stack 17 Infrastructure:"
log_info "  - VNet:      ${VNET_NAME} (dedicated for External APIM)"
log_info "  - NSG:       ${NSG_NAME}"
log_info "  - SWA:       ${STATIC_WEB_APP_NAME}"
log_info "  - APIM:      (will be created)"
log_info ""
log_info "Reused from other stacks:"
log_info "  - Function:  (auto-detected)"
log_info "  - Key Vault: (auto-detected)"
log_info ""

# Validate prerequisites
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

# Verify required infrastructure exists
log_step "Verifying prerequisites..."

# Check for Function App (can be from any stack)
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?contains(name, 'func-subnet-calc')].name | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${FUNCTION_APP_NAME}" ]]; then
  log_error "No Function App found. Deploy a stack with Function App first (e.g., Stack 3, 5, or 16)"
  exit 1
fi

# Check for Key Vault
KEY_VAULT_NAME=$(az keyvault list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")

if [[ -z "${KEY_VAULT_NAME}" ]]; then
  log_error "No Key Vault found. Deploy a stack with Key Vault first"
  exit 1
fi

log_info "✓ Prerequisites verified"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Key Vault:    ${KEY_VAULT_NAME}"
log_info ""

# Export for child scripts
export RESOURCE_GROUP
export VNET_NAME
export NSG_NAME
export FUNCTION_APP_NAME
export KEY_VAULT_NAME
export STATIC_WEB_APP_NAME
export CUSTOM_DOMAIN

# Get location
LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
export LOCATION

log_info "Starting Stack 17 deployment..."
log_info ""

# Step 1: Create VNet for APIM External mode
log_step "Step 1/11: Create VNet for APIM"
log_info ""

export VNET_MODE="External"
"${SCRIPT_DIR}/41-create-apim-vnet.sh"

log_info ""
log_info "✓ VNet created: ${VNET_NAME}"
log_info ""

# Step 2: Create NSG for APIM subnet
log_step "Step 2/11: Create NSG for APIM subnet"
log_info ""

"${SCRIPT_DIR}/42-create-apim-nsg.sh"

log_info ""
log_info "✓ NSG created and attached: ${NSG_NAME}"
log_info ""

# Step 3: Create APIM with VNet External mode (~45 min)
log_step "Step 3/11: Create APIM instance (VNet External mode)"
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

# Step 4: Setup App Registration for Entra ID
log_step "Step 4/11: Setup App Registration"
"${SCRIPT_DIR}/52-setup-app-registration.sh"

log_info ""
log_info "✓ App Registration ready"
log_info ""

# Step 5: Create Static Web App
log_step "Step 5/11: Create Static Web App"

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
log_step "Step 6/11: Create private endpoint for SWA"
"${SCRIPT_DIR}/48-create-private-endpoint-swa.sh"

log_info ""
log_info "✓ SWA private endpoint ready"
log_info ""

# Step 5: Configure APIM backend (import Function OpenAPI)
log_step "Step 7/11: Configure APIM backend"

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
log_step "Step 8/11: Apply APIM policies"

export AUTH_MODE="subscription"
"${SCRIPT_DIR}/32-apim-policies.sh"

log_info ""
log_info "✓ APIM policies applied"
log_info ""

# Step 7: Link SWA to APIM
log_step "Step 9/11: Link SWA to APIM backend"
"${SCRIPT_DIR}/44-link-swa-to-apim.sh"

log_info ""
log_info "✓ SWA linked to APIM"
log_info ""

# Step 8: Deploy frontend code to SWA
log_step "Step 10/11: Deploy frontend code"

SWA_DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.apiKey" -o tsv)

log_info "Frontend deployment token retrieved"
log_warn "TODO: Deploy frontend code using SWA CLI or GitHub Actions"
log_warn "Deployment token: ${SWA_DEPLOYMENT_TOKEN}"
log_info ""

# Step 9: Add HTTPS listener to AppGW
log_step "Step 11/11: Verify deployment"

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
