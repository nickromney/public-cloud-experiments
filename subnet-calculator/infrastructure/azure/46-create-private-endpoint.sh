#!/usr/bin/env bash
#
# Create private endpoint for Function App with private DNS zone
#
# This script creates a private endpoint for a Function App, enabling
# private connectivity through a VNet without exposing the Function App
# to the public internet. This is the highest security option for
# Azure Functions, suitable for regulated workloads and data sovereignty.
#
# Usage:
#   # Interactive mode (prompts for values)
#   ./46-create-private-endpoint.sh
#
#   # Specify all parameters
#   FUNCTION_APP_NAME="func-subnet-calc-123456" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-platform" \
#   SUBNET_NAME="snet-private-endpoints" \
#   ./46-create-private-endpoint.sh
#
# Parameters:
#   FUNCTION_APP_NAME - Name of the Function App
#   RESOURCE_GROUP    - Resource group containing the Function App
#   VNET_NAME         - Name of the VNet for private endpoint
#   SUBNET_NAME       - Name of the subnet for private endpoint
#   LOCATION          - Azure region (auto-detected from resource group if not set)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Function App must exist
#   - VNet and subnet must exist
#   - Subnet must have privateEndpointNetworkPolicies disabled
#   - User must have permissions to create network resources
#
# Created Resources:
#   - Private endpoint (connects Function App to VNet)
#   - Private DNS zone (privatelink.azurewebsites.net)
#   - Private DNS zone group (automatic DNS record management)
#   - VNet link (links DNS zone to VNet)
#
# Security Benefits:
#   - Function App not accessible from public internet
#   - Traffic stays within Azure backbone network
#   - Suitable for data sovereignty requirements
#   - Compatible with ExpressRoute and VPN connections
#
# Costs:
#   - Private endpoint: ~$7/month per endpoint
#   - Data processing: ~$0.01/GB (inbound free, outbound charged)
#   - Private DNS zone: ~$0.50/month
#
# Notes:
#   - Static Web Apps do not support private endpoints
#   - For SWA + Function App, use IP restrictions instead (45-configure-ip-restrictions.sh)
#   - Private endpoints require Function App Premium or higher (not supported on Consumption)
#   - For data sovereignty, also verify region with lib/verify-regions.sh

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

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Auto-detect or prompt for FUNCTION_APP_NAME
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  log_info "FUNCTION_APP_NAME not set. Looking for Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in resource group ${RESOURCE_GROUP}"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Function App: ${FUNCTION_APP_NAME}"
  else
    log_warn "Multiple Function Apps found:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Detected region from resource group: ${LOCATION}"
fi

# Check if VNET_NAME is set, otherwise prompt
if [[ -z "${VNET_NAME:-}" ]]; then
  log_error "VNET_NAME not set"
  log_error "Please specify the VNet name for the private endpoint"
  log_error ""
  log_error "Example:"
  log_error "  VNET_NAME=\"vnet-platform\" ./46-create-private-endpoint.sh"
  exit 1
fi

# Check if SUBNET_NAME is set, otherwise prompt
if [[ -z "${SUBNET_NAME:-}" ]]; then
  log_error "SUBNET_NAME not set"
  log_error "Please specify the subnet name for the private endpoint"
  log_error ""
  log_error "Example:"
  log_error "  SUBNET_NAME=\"snet-private-endpoints\" ./46-create-private-endpoint.sh"
  exit 1
fi

# Generate names
PE_NAME="pe-${FUNCTION_APP_NAME}"
DNS_ZONE_NAME="privatelink.azurewebsites.net"
VNET_LINK_NAME="vnet-link-${VNET_NAME}"

log_info ""
log_info "========================================="
log_info "Private Endpoint Configuration"
log_info "========================================="
log_info "Resource Group:     ${RESOURCE_GROUP}"
log_info "Function App:       ${FUNCTION_APP_NAME}"
log_info "Location:           ${LOCATION}"
log_info "VNet:               ${VNET_NAME}"
log_info "Subnet:             ${SUBNET_NAME}"
log_info "Private Endpoint:   ${PE_NAME}"
log_info "DNS Zone:           ${DNS_ZONE_NAME}"
log_info ""

# Verify Function App exists and get resource ID
log_step "Verifying Function App exists..."
if ! FUNCTION_APP_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "Function App ${FUNCTION_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Function App found: ${FUNCTION_APP_ID}"

# Check Function App SKU (private endpoints require Premium or higher)
log_step "Checking Function App SKU..."
FUNC_SKU=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku" -o tsv 2>/dev/null || echo "Unknown")

log_info "Function App SKU: ${FUNC_SKU}"

if [[ "${FUNC_SKU}" =~ (Dynamic|FlexConsumption) ]]; then
  log_error "Private endpoints are not supported on Consumption/Flex Consumption plans"
  log_error "Current SKU: ${FUNC_SKU}"
  log_error ""
  log_error "To use private endpoints, upgrade to Premium or higher:"
  log_error "  - Premium (EP1, EP2, EP3)"
  log_error "  - Dedicated App Service Plan (P1V2, P2V2, P3V2, etc.)"
  log_error ""
  log_error "For Consumption/Flex plans, use IP restrictions instead:"
  log_error "  ./45-configure-ip-restrictions.sh"
  exit 1
fi

# Verify VNet exists and get resource ID
log_step "Verifying VNet exists..."
if ! VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "VNet ${VNET_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "VNet found: ${VNET_ID}"

# Verify subnet exists and get resource ID
log_step "Verifying subnet exists..."
if ! SUBNET_ID=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "Subnet ${SUBNET_NAME} not found in VNet ${VNET_NAME}"
  exit 1
fi
log_info "Subnet found: ${SUBNET_ID}"

# Check if private endpoint network policies are disabled
log_step "Checking subnet network policies..."
PE_NETWORK_POLICIES=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "privateEndpointNetworkPolicies" -o tsv 2>/dev/null || echo "Enabled")

if [[ "${PE_NETWORK_POLICIES}" != "Disabled" ]]; then
  log_warn "Private endpoint network policies are not disabled on subnet"
  log_info "Disabling network policies for private endpoints..."

  az network vnet subnet update \
    --name "${SUBNET_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --disable-private-endpoint-network-policies true \
    --output none

  log_info "Network policies disabled"
fi

# Check if private endpoint already exists
log_step "Checking for existing private endpoint..."
if az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Private endpoint ${PE_NAME} already exists"
  log_error "Delete it first or use a different name"
  exit 1
fi

# Create private endpoint
log_step "Creating private endpoint..."
az network private-endpoint create \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --private-connection-resource-id "${FUNCTION_APP_ID}" \
  --group-id sites \
  --connection-name "${PE_NAME}-connection" \
  --output none

log_info "Private endpoint created: ${PE_NAME}"

# Create or verify private DNS zone
log_step "Checking for private DNS zone..."
if az network private-dns zone show \
  --name "${DNS_ZONE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Private DNS zone already exists: ${DNS_ZONE_NAME}"
else
  log_info "Creating private DNS zone: ${DNS_ZONE_NAME}..."
  az network private-dns zone create \
    --name "${DNS_ZONE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output none
  log_info "Private DNS zone created"
fi

# Create VNet link to DNS zone
log_step "Creating VNet link to DNS zone..."
if az network private-dns link vnet show \
  --name "${VNET_LINK_NAME}" \
  --zone-name "${DNS_ZONE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "VNet link already exists: ${VNET_LINK_NAME}"
else
  az network private-dns link vnet create \
    --name "${VNET_LINK_NAME}" \
    --zone-name "${DNS_ZONE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --virtual-network "${VNET_ID}" \
    --registration-enabled false \
    --output none
  log_info "VNet link created: ${VNET_LINK_NAME}"
fi

# Create private DNS zone group (automatic DNS record management)
log_step "Creating private DNS zone group..."
az network private-endpoint dns-zone-group create \
  --name "default" \
  --endpoint-name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --private-dns-zone "${DNS_ZONE_NAME}" \
  --zone-name "sites" \
  --output none

log_info "Private DNS zone group created"

# Get private endpoint details
log_step "Retrieving private endpoint details..."
PE_IP=$(az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

PE_FQDN=$(az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDnsConfigs[0].fqdn" -o tsv)

log_info ""
log_info "========================================="
log_info "Private Endpoint Created Successfully!"
log_info "========================================="
log_info "Function App:       ${FUNCTION_APP_NAME}"
log_info "Private Endpoint:   ${PE_NAME}"
log_info "Private IP:         ${PE_IP}"
log_info "Private FQDN:       ${PE_FQDN}"
log_info ""
log_info "DNS Configuration:"
log_info "  DNS Zone:     ${DNS_ZONE_NAME}"
log_info "  VNet Link:    ${VNET_LINK_NAME}"
log_info "  Auto-managed: Yes (via DNS zone group)"
log_info ""
log_info "Security Status:"
log_info "  - Function App accessible via private endpoint only"
log_info "  - DNS resolution automatic within VNet"
log_info "  - Traffic stays on Azure backbone network"
log_info ""
log_info "Next Steps:"
log_info "1. Disable public network access on Function App:"
log_info "   az functionapp update \\"
log_info "     --name ${FUNCTION_APP_NAME} \\"
log_info "     --resource-group ${RESOURCE_GROUP} \\"
log_info "     --set publicNetworkAccess=Disabled"
log_info ""
log_info "2. Test connectivity from a VM in the VNet:"
log_info "   nslookup ${FUNCTION_APP_NAME}.azurewebsites.net"
log_info "   curl https://${FUNCTION_APP_NAME}.azurewebsites.net/api/v1/health"
log_info ""
log_info "3. Verify data sovereignty compliance:"
log_info "   ./lib/verify-regions.sh"
log_info ""
log_info "To remove the private endpoint:"
log_info "  az network private-endpoint delete \\"
log_info "    --name ${PE_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP}"
log_info ""
