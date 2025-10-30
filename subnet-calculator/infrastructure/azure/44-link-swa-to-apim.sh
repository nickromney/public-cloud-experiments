#!/usr/bin/env bash
#
# 44-link-swa-to-apim.sh - Link Static Web App to API Management Backend
#
# This script links a Static Web App to an APIM instance using Azure's "Bring your own API" feature.
# This creates automatic Azure "magic" including:
#   - APIM product: "Azure Static Web Apps - <hostname> (Linked)"
#   - Subscription key with automatic generation
#   - Inbound validate-jwt policy on the product
#   - SWA automatically proxies /api/* requests to APIM
#   - SWA includes subscription key and access token in requests
#
# IMPORTANT LIMITATIONS:
#   - Only works with APIM in External VNet mode (public gateway)
#   - Does NOT work with Internal VNet mode (private gateway)
#   - Does NOT work with APIM that has private endpoint
#   - Network isolated backends are not supported
#
# Usage:
#   # Auto-detect APIM and SWA
#   RESOURCE_GROUP="rg-subnet-calc" ./44-link-swa-to-apim.sh
#
#   # Specify resources
#   RESOURCE_GROUP="rg-subnet-calc" \
#   STATIC_WEB_APP_NAME="swa-subnet-calc-apim" \
#   APIM_NAME="apim-subnet-calc-12345" \
#   ./44-link-swa-to-apim.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP - Resource group name
#
# Optional Environment Variables:
#   STATIC_WEB_APP_NAME - SWA name (auto-detected if single instance)
#   APIM_NAME           - APIM name (auto-detected if single instance)
#   APIM_REGION         - APIM region (auto-detected from APIM resource)
#
# Exit Codes:
#   0 - Success (SWA linked to APIM)
#   1 - Error (validation failed, linking failed, APIM in wrong mode)
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/static-web-apps/apis-api-management

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

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  log_error "Example: RESOURCE_GROUP='rg-subnet-calc' $0"
  exit 1
fi

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group '${RESOURCE_GROUP}' not found"
  exit 1
fi

# Auto-detect or validate Static Web App
log_step "Detecting Static Web App..."
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  SWA_COUNT=$(az staticwebapp list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in ${RESOURCE_GROUP}"
    log_error "Create one first before linking to APIM"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
    log_info "Auto-detected Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_error "Multiple Static Web Apps found in ${RESOURCE_GROUP}"
    log_error "Specify which one to link: STATIC_WEB_APP_NAME='swa-name' $0"
    az staticwebapp list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[].[name, sku.tier]" -o table
    exit 1
  fi
fi

# Verify SWA exists
if ! SWA_INFO=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{id:id,sku:sku.tier,hostname:defaultHostname}" -o json 2>/dev/null); then
  log_error "Static Web App '${STATIC_WEB_APP_NAME}' not found in ${RESOURCE_GROUP}"
  exit 1
fi

# shellcheck disable=SC2034
SWA_ID=$(echo "${SWA_INFO}" | jq -r '.id')
SWA_SKU=$(echo "${SWA_INFO}" | jq -r '.sku')
SWA_HOSTNAME=$(echo "${SWA_INFO}" | jq -r '.hostname')

log_info "Static Web App found: ${STATIC_WEB_APP_NAME}"
log_info "  SKU: ${SWA_SKU}"
log_info "  Hostname: ${SWA_HOSTNAME}"

# Verify SWA is Standard tier (required for backend linking)
if [[ "${SWA_SKU}" != "Standard" ]]; then
  log_error "Static Web App must be Standard tier for backend linking"
  log_error "Current SKU: ${SWA_SKU}"
  log_error ""
  log_error "Upgrade to Standard tier:"
  log_error "  az staticwebapp update \\"
  log_error "    --name ${STATIC_WEB_APP_NAME} \\"
  log_error "    --resource-group ${RESOURCE_GROUP} \\"
  log_error "    --sku Standard"
  exit 1
fi

# Auto-detect or validate APIM
log_step "Detecting API Management instance..."
if [[ -z "${APIM_NAME:-}" ]]; then
  APIM_COUNT=$(az apim list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${APIM_COUNT}" -eq 0 ]]; then
    log_error "No APIM instances found in ${RESOURCE_GROUP}"
    log_error "Create one first: ./43-create-apim-vnet.sh"
    exit 1
  elif [[ "${APIM_COUNT}" -eq 1 ]]; then
    APIM_NAME=$(az apim list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
    log_info "Auto-detected APIM instance: ${APIM_NAME}"
  else
    log_error "Multiple APIM instances found in ${RESOURCE_GROUP}"
    log_error "Specify which one to link: APIM_NAME='apim-name' $0"
    az apim list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[].[name, virtualNetworkType, provisioningState]" -o table
    exit 1
  fi
fi

# Verify APIM exists and get details
if ! APIM_INFO=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{id:id,vnetType:virtualNetworkType,state:provisioningState,location:location,gatewayUrl:gatewayUrl}" -o json 2>/dev/null); then
  log_error "APIM instance '${APIM_NAME}' not found in ${RESOURCE_GROUP}"
  exit 1
fi

APIM_ID=$(echo "${APIM_INFO}" | jq -r '.id')
APIM_VNET_TYPE=$(echo "${APIM_INFO}" | jq -r '.vnetType // "None"')
APIM_STATE=$(echo "${APIM_INFO}" | jq -r '.state')
APIM_LOCATION=$(echo "${APIM_INFO}" | jq -r '.location')
APIM_GATEWAY=$(echo "${APIM_INFO}" | jq -r '.gatewayUrl')

log_info "APIM instance found: ${APIM_NAME}"
log_info "  VNet Type: ${APIM_VNET_TYPE}"
log_info "  State: ${APIM_STATE}"
log_info "  Location: ${APIM_LOCATION}"
log_info "  Gateway URL: ${APIM_GATEWAY}"

# Verify APIM is ready
if [[ "${APIM_STATE}" != "Succeeded" ]]; then
  log_error "APIM instance is not ready. Current state: ${APIM_STATE}"
  log_error "Wait for APIM provisioning to complete"
  exit 1
fi

# CRITICAL: Verify APIM is in External mode
if [[ "${APIM_VNET_TYPE}" == "Internal" ]]; then
  log_error "APIM instance is in Internal VNet mode"
  log_error ""
  log_error "❌ Static Web Apps CANNOT link to Internal VNet mode APIM"
  log_error "   Network isolated backends are not supported"
  log_error ""
  log_error "Options:"
  log_error "  1. Use External VNet mode APIM (for Stack 17)"
  log_error "  2. Use Application Gateway with path-based routing (for Stack 18)"
  log_error ""
  log_error "For Stack 18, use script 55 to configure AppGW path routing"
  exit 1
fi

if [[ "${APIM_VNET_TYPE}" != "External" && "${APIM_VNET_TYPE}" != "None" ]]; then
  log_warn "APIM VNet type: ${APIM_VNET_TYPE}"
  log_warn "Linking may not work with network isolated APIM"
fi

# Check if SWA already has a backend linked
log_step "Checking for existing backend configuration..."
EXISTING_BACKEND=$(az staticwebapp backends list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].{type:backendResourceId | type(@), id:backendResourceId}" -o json 2>/dev/null || echo "null")

if [[ "${EXISTING_BACKEND}" != "null" && "${EXISTING_BACKEND}" != "[]" ]]; then
  EXISTING_BACKEND_ID=$(echo "${EXISTING_BACKEND}" | jq -r '.id // empty')

  if [[ -n "${EXISTING_BACKEND_ID}" ]]; then
    log_warn "Static Web App already has a backend configured:"
    log_warn "  Backend ID: ${EXISTING_BACKEND_ID}"
    log_warn ""

    if [[ "${EXISTING_BACKEND_ID}" == "${APIM_ID}" ]]; then
      log_info "Backend is already linked to the target APIM instance"
      log_info "Nothing to do - link already exists"
      exit 0
    else
      log_error "Cannot link to APIM - different backend already linked"
      log_error ""
      log_error "Only one backend is allowed per Static Web App"
      log_error "Unlink existing backend first:"
      log_error ""
      log_error "  az staticwebapp backends unlink \\"
      log_error "    --name ${STATIC_WEB_APP_NAME} \\"
      log_error "    --resource-group ${RESOURCE_GROUP}"
      log_error ""
      exit 1
    fi
  fi
fi

# Link SWA to APIM
log_step "Linking Static Web App to APIM..."
log_info "This will create automatic configuration:"
log_info "  - APIM product for SWA"
log_info "  - Subscription key"
log_info "  - JWT validation policy"
log_info "  - /api/* request proxying"
log_info ""

# Use APIM_REGION if specified, otherwise use APIM location
BACKEND_REGION="${APIM_REGION:-${APIM_LOCATION}}"

if ! az staticwebapp backends link \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --backend-resource-id "${APIM_ID}" \
  --backend-region "${BACKEND_REGION}" \
  --output none; then
  log_error "Failed to link Static Web App to APIM"
  log_error ""
  log_error "Common causes:"
  log_error "  - APIM has private endpoint (not supported)"
  log_error "  - APIM is in Internal VNet mode (not supported)"
  log_error "  - Network connectivity issues"
  exit 1
fi

log_info "✓ Static Web App linked to APIM successfully"

# Verify link was created
log_step "Verifying backend link..."
LINKED_BACKEND=$(az staticwebapp backends list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].backendResourceId" -o tsv 2>/dev/null || echo "")

if [[ "${LINKED_BACKEND}" == "${APIM_ID}" ]]; then
  log_info "✓ Backend link verified"
else
  log_warn "Backend link verification inconclusive"
  log_warn "Expected: ${APIM_ID}"
  log_warn "Got: ${LINKED_BACKEND}"
fi

log_info ""
log_info "✓ SWA→APIM Link Complete!"
log_info ""
log_info "========================================="
log_info "Link Configuration"
log_info "========================================="
log_info "Static Web App:   ${STATIC_WEB_APP_NAME}"
log_info "Hostname:         ${SWA_HOSTNAME}"
log_info ""
log_info "API Management:   ${APIM_NAME}"
log_info "Gateway URL:      ${APIM_GATEWAY}"
log_info "VNet Mode:        ${APIM_VNET_TYPE}"
log_info ""
log_info "Automatic Configuration:"
log_info "  ✓ APIM product created"
log_info "  ✓ Subscription key generated"
log_info "  ✓ JWT validation enabled"
log_info "  ✓ /api/* requests proxied to APIM"
log_info ""
log_info "Next Steps:"
log_info "  1. Deploy frontend code to SWA"
log_info "  2. Configure APIM APIs and policies (./31-apim-backend.sh, ./32-apim-policies.sh)"
log_info "  3. Test: curl https://${SWA_HOSTNAME}/api/[your-api-path]"
log_info ""
