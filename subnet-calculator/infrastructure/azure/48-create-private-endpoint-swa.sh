#!/usr/bin/env bash
#
# Create private endpoint for Static Web App with private DNS zone
#
# This script creates a private endpoint for an Azure Static Web App, enabling
# private connectivity through a VNet. When configured, the SWA will only be
# accessible from the VNet (or via Application Gateway if configured).
#
# Usage:
#   # Interactive mode (prompts for values)
#   ./48-create-private-endpoint-swa.sh
#
#   # Specify all parameters
#   STATIC_WEB_APP_NAME="swa-subnet-calc-private" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-platform" \
#   SUBNET_NAME="snet-private-endpoints" \
#   ./48-create-private-endpoint-swa.sh
#
# Parameters:
#   STATIC_WEB_APP_NAME - Name of the Static Web App
#   RESOURCE_GROUP      - Resource group containing the Static Web App
#   VNET_NAME           - Name of the VNet for private endpoint
#   SUBNET_NAME         - Name of the subnet for private endpoint
#   LOCATION            - Azure region (auto-detected from resource group if not set)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Static Web App must exist and be Standard tier or higher
#   - VNet and subnet must exist
#   - Subnet must have privateEndpointNetworkPolicies disabled
#   - User must have permissions to create network resources
#
# Created Resources:
#   - Private endpoint (connects Static Web App to VNet)
#   - Private DNS zone (privatelink.<number>.azurestaticapps.net)
#   - Private DNS zone group (automatic DNS record management)
#   - VNet link (links DNS zone to VNet)
#
# Security Benefits:
#   - Static Web App not accessible from public internet
#   - Traffic stays within Azure backbone network
#   - Can be exposed via Application Gateway for controlled public access
#   - Compatible with ExpressRoute and VPN connections
#
# Costs:
#   - Private endpoint: Free (no per-endpoint charge)
#   - Data processing: ~$0.01/GB (inbound free, outbound charged)
#   - Private DNS zone: ~$0.50/month
#
# Notes:
#   - Requires Standard or Enterprise tier SWA
#   - DNS zone format is region-specific: privatelink.<number>.azurestaticapps.net
#   - After creation, SWA will only be accessible from VNet
#   - Use Application Gateway to provide public access if needed
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/static-web-apps/private-endpoint

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

# Auto-detect or prompt for STATIC_WEB_APP_NAME
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_info "STATIC_WEB_APP_NAME not set. Looking for Static Web Apps..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in resource group ${RESOURCE_GROUP}"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_warn "Multiple Static Web Apps found:"
    # Use select_function_app utility as template (we can reuse the pattern)
    mapfile -t SWA_NAMES < <(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv)
    PS3="Select a Static Web App: "
    select STATIC_WEB_APP_NAME in "${SWA_NAMES[@]}"; do
      if [[ -n "${STATIC_WEB_APP_NAME}" ]]; then
        break
      fi
    done
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
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
  log_error "  VNET_NAME=\"vnet-platform\" ./48-create-private-endpoint-swa.sh"
  exit 1
fi

# Check if SUBNET_NAME is set, otherwise prompt
if [[ -z "${SUBNET_NAME:-}" ]]; then
  log_error "SUBNET_NAME not set"
  log_error "Please specify the subnet name for the private endpoint"
  log_error ""
  log_error "Example:"
  log_error "  SUBNET_NAME=\"snet-private-endpoints\" ./48-create-private-endpoint-swa.sh"
  exit 1
fi

# Generate names
PE_NAME="pe-${STATIC_WEB_APP_NAME}"

log_info ""
log_info "========================================="
log_info "SWA Private Endpoint Configuration"
log_info "========================================="
log_info "Resource Group:     ${RESOURCE_GROUP}"
log_info "Static Web App:     ${STATIC_WEB_APP_NAME}"
log_info "Location:           ${LOCATION}"
log_info "VNet:               ${VNET_NAME}"
log_info "Subnet:             ${SUBNET_NAME}"
log_info "Private Endpoint:   ${PE_NAME}"
log_info ""

# Verify Static Web App exists and get resource ID
log_step "Verifying Static Web App exists..."
if ! SWA_ID=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Static Web App found: ${SWA_ID}"

# Check Static Web App SKU (private endpoints require Standard or Enterprise)
log_step "Checking Static Web App SKU..."
SWA_SKU=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.name" -o tsv 2>/dev/null || echo "Unknown")

log_info "Static Web App SKU: ${SWA_SKU}"

if [[ "${SWA_SKU}" == "Free" ]]; then
  log_error "Private endpoints are not supported on Free tier Static Web Apps"
  log_error "Current SKU: ${SWA_SKU}"
  log_error ""
  log_error "To use private endpoints, upgrade to Standard or Enterprise tier"
  log_error ""
  log_error "Upgrade command:"
  log_error "  az staticwebapp update \\"
  log_error "    --name ${STATIC_WEB_APP_NAME} \\"
  log_error "    --resource-group ${RESOURCE_GROUP} \\"
  log_error "    --sku Standard"
  exit 1
fi

# Get the SWA default hostname to determine DNS zone
SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostname" -o tsv)

# Extract the region-specific number from hostname (e.g., "nice-island-12345.3.azurestaticapps.net" -> "3")
# The format is: <name>.<number>.azurestaticapps.net
if [[ "${SWA_HOSTNAME}" =~ \.([0-9]+)\.azurestaticapps\.net$ ]]; then
  SWA_REGION_NUMBER="${BASH_REMATCH[1]}"
  DNS_ZONE_NAME="privatelink.${SWA_REGION_NUMBER}.azurestaticapps.net"
  log_info "Detected SWA region number: ${SWA_REGION_NUMBER}"
else
  log_error "Could not determine SWA region number from hostname: ${SWA_HOSTNAME}"
  log_error "Expected format: <name>.<number>.azurestaticapps.net"
  exit 1
fi

VNET_LINK_NAME="vnet-link-${VNET_NAME}"

log_info "DNS Zone:           ${DNS_ZONE_NAME}"
log_info ""

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

  log_info "Private endpoint ${PE_NAME} already exists - verifying configuration..."

  # Get the target resource ID from existing private endpoint
  EXISTING_TARGET=$(az network private-endpoint show \
    --name "${PE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "privateLinkServiceConnections[0].privateLinkServiceId" -o tsv 2>/dev/null || echo "")

  # Get the subnet ID from existing private endpoint
  EXISTING_SUBNET=$(az network private-endpoint show \
    --name "${PE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "subnet.id" -o tsv 2>/dev/null || echo "")

  # Verify it's connected to the correct Static Web App
  if [[ "${EXISTING_TARGET}" == "${SWA_ID}" ]]; then
    log_info "Private endpoint is correctly connected to ${STATIC_WEB_APP_NAME}"

    # Verify it's in the correct subnet
    if [[ "${EXISTING_SUBNET}" == "${SUBNET_ID}" ]]; then
      log_info "Private endpoint is in the correct subnet: ${SUBNET_NAME}"
      log_info "Configuration is correct - skipping private endpoint creation"
      log_info ""

      # Get details for display
      PE_IP=$(az network private-endpoint show \
        --name "${PE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "customDnsConfigs[0].ipAddresses[0]" -o tsv 2>/dev/null || echo "N/A")

      log_info "Private endpoint: ${PE_NAME}"
      log_info "Private IP: ${PE_IP}"
      log_info "Status: Already configured (idempotent)"
      exit 0
    else
      log_warn "Private endpoint exists but is in a different subnet"
      log_warn "  Expected subnet: ${SUBNET_ID}"
      log_warn "  Current subnet: ${EXISTING_SUBNET}"
      log_error "Please delete the private endpoint and re-run:"
      log_error "  az network private-endpoint delete --name ${PE_NAME} --resource-group ${RESOURCE_GROUP}"
      exit 1
    fi
  else
    log_warn "Private endpoint ${PE_NAME} exists but is connected to a different resource"
    log_warn "  Expected: ${SWA_ID}"
    log_warn "  Current: ${EXISTING_TARGET}"
    log_error "Please delete the private endpoint and re-run:"
    log_error "  az network private-endpoint delete --name ${PE_NAME} --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi
fi

# Create private endpoint
log_step "Creating private endpoint for Static Web App..."
az network private-endpoint create \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --vnet-name "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --private-connection-resource-id "${SWA_ID}" \
  --group-id staticSites \
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
  --zone-name "staticSites" \
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
log_info "SWA Private Endpoint Created!"
log_info "========================================="
log_info "Static Web App:     ${STATIC_WEB_APP_NAME}"
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
log_info "  - Static Web App accessible via private endpoint only"
log_info "  - DNS resolution automatic within VNet"
log_info "  - Traffic stays on Azure backbone network"
log_info ""
log_info "Next Steps:"
log_info "1. Test connectivity from a VM in the VNet:"
log_info "   nslookup ${SWA_HOSTNAME}"
log_info "   curl https://${SWA_HOSTNAME}"
log_info ""
log_info "2. (Optional) Add Application Gateway for public access:"
log_info "   - Create Application Gateway in the VNet"
log_info "   - Configure backend pool with private IP: ${PE_IP}"
log_info "   - Configure HTTPS listener and routing rules"
log_info ""
log_info "3. (Optional) Verify custom domain still works:"
log_info "   - Custom domains will resolve to private IP within VNet"
log_info "   - External access will be blocked unless via App Gateway"
log_info ""
log_info "To remove the private endpoint:"
log_info "  az network private-endpoint delete \\"
log_info "    --name ${PE_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP}"
log_info ""
