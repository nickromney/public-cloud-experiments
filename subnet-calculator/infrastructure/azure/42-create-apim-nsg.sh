#!/usr/bin/env bash
#
# 42-create-apim-nsg.sh - Create NSG for Azure API Management
#
# This script creates a Network Security Group with the required rules
# for Azure API Management VNet integration (both External and Internal modes).
#
# APIM requires an NSG to be attached to its subnet with specific rules:
# - Management endpoint (port 3443) for Azure portal and PowerShell
# - Load Balancer health probes
# - Storage for APIM configuration and logs (port 443)
# - Azure SQL for APIM internal storage (port 1433)
# - Azure Monitor diagnostics (port 1886, 443)
# - Client traffic ports (80, 443 for API access)
#
# Reference: https://aka.ms/apiminternalvnet
#
# Usage:
#   # External mode (Stack 17)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-subnet-calc-apim-external" \
#   NSG_NAME="nsg-apim-external" \
#   ./42-create-apim-nsg.sh
#
#   # Internal mode (Stack 18)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-subnet-calc-apim-internal" \
#   NSG_NAME="nsg-apim-internal" \
#   ./42-create-apim-nsg.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP     - Resource group name
#   VNET_NAME          - Virtual network name
#
# Optional Environment Variables:
#   NSG_NAME           - NSG name (default: nsg-apim)
#   APIM_SUBNET_NAME   - Subnet to attach NSG to (default: snet-apim)
#   LOCATION           - Azure region (auto-detected from resource group)
#
# Exit Codes:
#   0 - Success (NSG created and attached)
#   1 - Error (validation failed, creation failed)
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_step() {
  echo -e "${BLUE}[STEP]${NC} $*"
}

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

if [[ -z "${VNET_NAME:-}" ]]; then
  log_error "VNET_NAME environment variable is required"
  exit 1
fi

# Set defaults
readonly NSG_NAME="${NSG_NAME:-nsg-apim}"
readonly APIM_SUBNET_NAME="${APIM_SUBNET_NAME:-snet-apim}"

# Auto-detect location from resource group if not provided
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Auto-detected location: ${LOCATION}"
fi

log_info ""
log_info "======================================="
log_info "APIM NSG Creation"
log_info "======================================="
log_info "Resource Group: ${RESOURCE_GROUP}"
log_info "Location:       ${LOCATION}"
log_info "NSG Name:       ${NSG_NAME}"
log_info "VNet:           ${VNET_NAME}"
log_info "Subnet:         ${APIM_SUBNET_NAME}"
log_info ""

# Check if NSG already exists
log_step "Checking if NSG already exists..."
if az network nsg show --resource-group "${RESOURCE_GROUP}" --name "${NSG_NAME}" &>/dev/null; then
  log_info "NSG '${NSG_NAME}' already exists"

  # Check if it's already attached to the subnet
  CURRENT_NSG=$(az network vnet subnet show \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_NAME}" \
    --name "${APIM_SUBNET_NAME}" \
    --query "networkSecurityGroup.id" -o tsv 2>/dev/null || echo "")

  if [[ -n "${CURRENT_NSG}" ]] && [[ "${CURRENT_NSG}" == *"${NSG_NAME}"* ]]; then
    log_info "NSG is already attached to subnet ${APIM_SUBNET_NAME}"
    log_info "✓ NSG configuration complete"
    exit 0
  else
    log_info "NSG exists but not attached to subnet. Attaching..."
  fi
else
  log_step "Creating NSG for APIM..."
  az network nsg create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${NSG_NAME}" \
    --location "${LOCATION}" \
    --output none

  log_info "✓ NSG created"

  log_step "Adding required inbound rules..."

  # Rule 1: Management endpoint for Azure portal and PowerShell
  log_info "Adding rule: Allow APIM Management (port 3443)..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-APIM-Management" \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "ApiManagement" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges 3443 \
    --output none

  # Rule 2: Load Balancer health probes
  log_info "Adding rule: Allow Load Balancer health probes..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-LoadBalancer" \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol "*" \
    --source-address-prefixes "AzureLoadBalancer" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges "*" \
    --output none

  # Rule 3: Client traffic (HTTP/HTTPS) - needed for External mode
  log_info "Adding rule: Allow Client Traffic (ports 80, 443)..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-Client-Traffic" \
    --priority 120 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "Internet" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges 80 443 \
    --output none

  log_info "✓ Inbound rules created"

  log_step "Adding required outbound rules..."

  # Rule 4: Storage access for APIM configuration
  log_info "Adding rule: Allow Storage (port 443)..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-Storage" \
    --priority 100 \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "VirtualNetwork" \
    --source-port-ranges "*" \
    --destination-address-prefixes "Storage" \
    --destination-port-ranges 443 \
    --output none

  # Rule 5: Azure SQL for APIM internal storage
  log_info "Adding rule: Allow Azure SQL (port 1433)..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-AzureSQL" \
    --priority 110 \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "VirtualNetwork" \
    --source-port-ranges "*" \
    --destination-address-prefixes "Sql" \
    --destination-port-ranges 1433 \
    --output none

  # Rule 6: Azure Monitor for diagnostics
  log_info "Adding rule: Allow Azure Monitor (port 1886, 443)..."
  az network nsg rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --nsg-name "${NSG_NAME}" \
    --name "Allow-AzureMonitor" \
    --priority 120 \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "VirtualNetwork" \
    --source-port-ranges "*" \
    --destination-address-prefixes "AzureMonitor" \
    --destination-port-ranges 1886 443 \
    --output none

  log_info "✓ Outbound rules created"
fi

# Attach NSG to APIM subnet
log_step "Attaching NSG to subnet ${APIM_SUBNET_NAME}..."
az network vnet subnet update \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet-name "${VNET_NAME}" \
  --name "${APIM_SUBNET_NAME}" \
  --network-security-group "${NSG_NAME}" \
  --output none

log_info "✓ NSG attached to subnet"
log_info ""
log_info "======================================="
log_info "NSG Configuration Complete"
log_info "======================================="
log_info "NSG Name:    ${NSG_NAME}"
log_info "Attached to: ${VNET_NAME}/${APIM_SUBNET_NAME}"
log_info ""
log_info "The subnet is now ready for APIM deployment"
log_info ""
