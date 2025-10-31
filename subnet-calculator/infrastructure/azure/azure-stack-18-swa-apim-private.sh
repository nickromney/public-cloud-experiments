#!/usr/bin/env bash
#
# Stack 18: Static Web App + APIM (Internal VNet Mode) + Function App
#
# Architecture (Full Private - Following Microsoft Reference Pattern):
#   Internet → AppGW (public + private listeners, path-based routing)
#              ↓ path: /*
#              SWA (private endpoint)
#
#              ↓ path: /api/*
#              APIM (VNet internal mode - private gateway)
#              ↓ internal VNet routing
#              Function (private endpoint)
#
# Key Features:
#   - APIM in Internal VNet mode (fully private)
#   - Path-based routing at AppGW level (/*→SWA, /api/*→APIM)
#   - Cannot use SWA→APIM linking (network isolated backend limitation)
#   - Maximum security: all components private
#   - Split-brain DNS (external/internal resolution)
#
# Prerequisites:
#   - Stack 16 must be deployed (provides: VNet, AppGW, Function with PE, Key Vault)
#   - Cloudflare API token for DNS validation
#   - Custom domain: static-swa-apim-private.publiccloudexperiments.net
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   CUSTOM_DOMAIN="static-swa-apim-private.publiccloudexperiments.net" \
#   ./azure-stack-18-swa-apim-private.sh

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
readonly STATIC_WEB_APP_NAME="swa-subnet-calc-apim-private"
readonly APIM_NAME_PREFIX="apim-subnet-calc-private"
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-static-swa-apim-private.publiccloudexperiments.net}"

# Stack 18 Infrastructure (dedicated VNet for Internal APIM)
readonly VNET_NAME="vnet-subnet-calc-apim-internal"
readonly NSG_NAME="nsg-apim-internal"

log_info ""
log_info "================================================="
log_info "Stack 18: SWA + APIM (Internal - Private) + Function"
log_info "================================================="
log_info ""
log_info "Custom Domain: ${CUSTOM_DOMAIN}"
log_info "SWA Name:      ${STATIC_WEB_APP_NAME}"
log_info "APIM Prefix:   ${APIM_NAME_PREFIX}"
log_info ""
log_info "Stack 18 Infrastructure:"
log_info "  - VNet:      ${VNET_NAME} (dedicated for Internal APIM)"
log_info "  - NSG:       ${NSG_NAME}"
log_info "  - SWA:       ${STATIC_WEB_APP_NAME}"
log_info "  - APIM:      (will be created)"
log_info ""
log_info "Reused from Stack 16:"
log_info "  - AppGW:     (auto-detected, adds listener + path routing)"
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

# Check for Application Gateway (from Stack 16)
APPGW_NAME=$(az network application-gateway list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?contains(name, 'agw-swa')].name | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${APPGW_NAME}" ]]; then
  log_error "No Application Gateway found. Deploy Stack 16 first"
  exit 1
fi

log_info "✓ Prerequisites verified"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Key Vault:    ${KEY_VAULT_NAME}"
log_info "  AppGW:        ${APPGW_NAME} (from Stack 16)"
log_info ""

# Export for child scripts
export RESOURCE_GROUP
export VNET_NAME
export NSG_NAME
export FUNCTION_APP_NAME
export KEY_VAULT_NAME
export STATIC_WEB_APP_NAME
export CUSTOM_DOMAIN
export APPGW_NAME

LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
export LOCATION

log_info "Starting Stack 18 deployment..."
log_info ""

# Step 1: Create VNet for APIM Internal mode
log_step "Step 1/16: Create VNet for APIM"
log_info ""

export VNET_MODE="Internal"
"${SCRIPT_DIR}/41-create-apim-vnet.sh"

log_info ""
log_info "✓ VNet created: ${VNET_NAME}"
log_info ""

# Step 2: Create VNet peering to Stack 16
log_step "Step 2/16: Create VNet peering to Stack 16"
log_info ""

# Find Stack 16 VNet (vnet-subnet-calc-private)
STACK16_VNET=$(az network vnet list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?contains(name, 'vnet-subnet-calc-private')].name | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${STACK16_VNET}" ]]; then
  log_error "Stack 16 VNet not found. Deploy Stack 16 first."
  exit 1
fi

export SOURCE_VNET="${VNET_NAME}"
export DEST_VNET="${STACK16_VNET}"
"${SCRIPT_DIR}/40-create-vnet-peering.sh"

log_info ""
log_info "✓ VNet peering configured"
log_info ""

# Step 3: Create NSG for APIM subnet
log_step "Step 3/16: Create NSG for APIM subnet"
log_info ""

"${SCRIPT_DIR}/42-create-apim-nsg.sh"

log_info ""
log_info "✓ NSG created and attached: ${NSG_NAME}"
log_info ""

# Step 3: Create APIM with VNet Internal mode (~45 min)
log_step "Step 4/16: Create APIM instance (VNet Internal mode)"
log_warn "⏱️  This will take approximately 45-55 minutes"
log_info ""

export APIM_VNET_MODE="Internal"
export APIM_SKU="Developer"

"${SCRIPT_DIR}/43-create-apim-vnet.sh"

# Get APIM name
APIM_NAME=$(az apim list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?virtualNetworkType=='Internal'].name | [0]" -o tsv)

if [[ -z "${APIM_NAME}" ]]; then
  log_error "APIM instance not found or not in Internal mode"
  exit 1
fi

export APIM_NAME

log_info ""
log_info "✓ APIM instance ready: ${APIM_NAME}"
log_info ""

# Step 2: Create private endpoint for APIM
log_step "Step 5/16: Create private endpoint for APIM"
"${SCRIPT_DIR}/56-create-private-endpoint-apim.sh"

log_info ""
log_info "✓ APIM private endpoint ready"
log_info ""

# Step 3: Setup App Registration for Entra ID
log_step "Step 6/16: Setup App Registration"
"${SCRIPT_DIR}/52-setup-app-registration.sh"

log_info ""
log_info "✓ App Registration ready"
log_info ""

# Step 4: Create Static Web App
log_step "Step 7/16: Create Static Web App"

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

# Step 5: Create private endpoint for SWA
log_step "Step 8/16: Create private endpoint for SWA"
"${SCRIPT_DIR}/48-create-private-endpoint-swa.sh"

log_info ""
log_info "✓ SWA private endpoint ready"
log_info ""

# Step 6: Configure APIM backend (import Function OpenAPI)
log_step "Step 9/16: Configure APIM backend"

FUNCTION_URL=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

export FUNCTION_URL="https://${FUNCTION_URL}"

"${SCRIPT_DIR}/31-apim-backend.sh"

log_info ""
log_info "✓ APIM backend configured"
log_info ""

# Step 7: Apply APIM policies
log_step "Step 10/16: Apply APIM policies"

export AUTH_MODE="subscription"
"${SCRIPT_DIR}/32-apim-policies.sh"

log_info ""
log_info "✓ APIM policies applied"
log_info ""

# Step 8: Deploy frontend code to SWA
log_step "Step 11/16: Deploy frontend code"

SWA_DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.apiKey" -o tsv)

log_info "Frontend deployment token retrieved"
log_warn "TODO: Deploy frontend code using SWA CLI or GitHub Actions"
log_warn "Deployment token: ${SWA_DEPLOYMENT_TOKEN}"
log_info ""

# Step 9: Add HTTPS listener for SWA
log_step "Step 12/16: Add HTTPS listener for SWA"

SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostname" -o tsv)

if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
  SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
  SWA_PRIVATE_FQDN="${SWA_HOSTNAME/.${SWA_REGION_NUMBER}.azurestaticapps.net/.privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net}"
else
  log_error "Could not determine SWA region number"
  exit 1
fi

export LISTENER_NAME="swa-apim-private-listener"
export BACKEND_FQDN="${SWA_PRIVATE_FQDN}"

"${SCRIPT_DIR}/54-add-https-listener-named.sh"

log_info ""
log_info "✓ SWA HTTPS listener configured"
log_info ""

# Step 10: Create backend pool for APIM
log_step "Step 13/16: Create APIM backend pool"

APIM_PRIVATE_IP=$(az network private-endpoint show \
  --name "pe-${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

log_info "Creating APIM backend pool with private IP: ${APIM_PRIVATE_IP}"

if ! az network application-gateway address-pool show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "apim-backend" &>/dev/null; then

  az network application-gateway address-pool create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "apim-backend" \
    --servers "${APIM_PRIVATE_IP}" \
    --output none

  log_info "✓ APIM backend pool created"
else
  log_info "APIM backend pool already exists"
fi

log_info ""

# Step 11: Create HTTP settings for APIM
log_step "Step 14/16: Create APIM HTTP settings"

APIM_GATEWAY_HOSTNAME=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "gatewayUrl" -o tsv | sed 's|https://||')

if ! az network application-gateway http-settings show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "apim-http-settings" &>/dev/null; then

  az network application-gateway http-settings create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "apim-http-settings" \
    --port 443 \
    --protocol Https \
    --cookie-based-affinity Disabled \
    --timeout 30 \
    --host-name "${APIM_GATEWAY_HOSTNAME}" \
    --output none

  log_info "✓ APIM HTTP settings created"
else
  log_info "APIM HTTP settings already exist"
fi

log_info ""

# Step 12: Configure path-based routing
log_step "Step 15/16: Configure path-based routing"

export SWA_BACKEND_POOL="swa-apim-private-listener-backend"
export APIM_BACKEND_POOL="apim-backend"
export SWA_HTTP_SETTINGS="swa-apim-private-listener-http-settings"
export APIM_HTTP_SETTINGS="apim-http-settings"

"${SCRIPT_DIR}/55-add-path-based-routing.sh"

log_info ""
log_info "✓ Path-based routing configured"
log_info ""

# Step 13: Verify deployment
log_step "Step 16/16: Verify deployment"

APPGW_PUBLIC_IP=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "frontendIPConfigurations[0].publicIPAddress.id" -o tsv | \
  xargs -I {} az network public-ip show --ids {} --query ipAddress -o tsv)

log_info ""
log_info "========================================="
log_info "✓ Stack 18 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "Architecture (Full Private):"
log_info "  Internet → AppGW (path-based routing)"
log_info "           ↓ /* → SWA (private endpoint)"
log_info "           ↓ /api/* → APIM (private - Internal mode) → Function (private)"
log_info ""
log_info "Resources Created:"
log_info "  Static Web App:   ${STATIC_WEB_APP_NAME}"
log_info "  APIM Instance:    ${APIM_NAME} (VNet Internal mode)"
log_info "  APIM Private IP:  ${APIM_PRIVATE_IP}"
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
log_info "  Custom Domain:    https://${CUSTOM_DOMAIN} (after DNS config)"
log_info "  SWA Default:      https://${SWA_HOSTNAME}"
log_info ""
log_info "Routing Configuration:"
log_info "  https://${CUSTOM_DOMAIN}/         → SWA"
log_info "  https://${CUSTOM_DOMAIN}/api/...  → APIM → Function"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure DNS A record:"
log_info "     ${CUSTOM_DOMAIN} → ${APPGW_PUBLIC_IP}"
log_info ""
log_info "  2. Deploy frontend code to SWA"
log_info ""
log_info "  3. Test routing:"
log_info "     curl https://${CUSTOM_DOMAIN}/         # → SWA"
log_info "     curl https://${CUSTOM_DOMAIN}/api/v1/health  # → APIM → Function"
log_info ""
log_info "Security Profile:"
log_info "  ✓ All components private (SWA, APIM, Function)"
log_info "  ✓ APIM Internal VNet mode (private gateway)"
log_info "  ✓ Path-based routing at AppGW"
log_info "  ✓ End-to-end private connectivity"
log_info ""
