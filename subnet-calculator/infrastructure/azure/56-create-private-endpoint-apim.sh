#!/usr/bin/env bash
#
# 56-create-private-endpoint-apim.sh - Create Private Endpoint for API Management
#
# This script creates a private endpoint for an APIM instance (Internal VNet mode only).
# The private endpoint enables private connectivity to APIM gateway from within the VNet.
#
# IMPORTANT: Only works with APIM in Internal VNet mode
# For External mode APIM, private endpoint is not needed (gateway is already public)
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   APIM_NAME="apim-subnet-calc-12345" \
#   VNET_NAME="vnet-platform" \
#   ./56-create-private-endpoint-apim.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP - Resource group name
#   APIM_NAME      - APIM instance name
#   VNET_NAME      - Virtual network name
#
# Optional Environment Variables:
#   PE_SUBNET_NAME - Private endpoint subnet (default: snet-privateendpoints)
#   PE_NAME        - Private endpoint name (default: pe-{apim-name})
#   LOCATION       - Azure region (auto-detected from resource group)
#
# Exit Codes:
#   0 - Success (private endpoint created)
#   1 - Error (validation failed, APIM not in Internal mode)
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/api-management/private-endpoint

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

# Validate required variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

if [[ -z "${APIM_NAME:-}" ]]; then
  log_error "APIM_NAME environment variable is required"
  exit 1
fi

if [[ -z "${VNET_NAME:-}" ]]; then
  log_error "VNET_NAME environment variable is required"
  exit 1
fi

# Configuration with defaults
readonly PE_SUBNET_NAME="${PE_SUBNET_NAME:-snet-privateendpoints}"
readonly PE_NAME="${PE_NAME:-pe-${APIM_NAME}}"

# Get location
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
fi

log_info "Configuration:"
log_info "  Resource Group:    ${RESOURCE_GROUP}"
log_info "  APIM Name:         ${APIM_NAME}"
log_info "  VNet:              ${VNET_NAME}"
log_info "  PE Subnet:         ${PE_SUBNET_NAME}"
log_info "  Private Endpoint:  ${PE_NAME}"
log_info "  Location:          ${LOCATION}"
log_info ""

# Verify APIM exists and get details
log_step "Verifying APIM instance..."
if ! APIM_INFO=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{id:id,vnetType:virtualNetworkType,state:provisioningState}" -o json 2>/dev/null); then
  log_error "APIM instance '${APIM_NAME}' not found"
  exit 1
fi

APIM_ID=$(echo "${APIM_INFO}" | jq -r '.id')
APIM_VNET_TYPE=$(echo "${APIM_INFO}" | jq -r '.vnetType // "None"')
APIM_STATE=$(echo "${APIM_INFO}" | jq -r '.state')

log_info "APIM found: ${APIM_NAME}"
log_info "  VNet Type: ${APIM_VNET_TYPE}"
log_info "  State: ${APIM_STATE}"

# Verify APIM is ready
if [[ "${APIM_STATE}" != "Succeeded" ]]; then
  log_error "APIM is not ready. State: ${APIM_STATE}"
  exit 1
fi

# Verify APIM is in Internal mode
if [[ "${APIM_VNET_TYPE}" != "Internal" ]]; then
  log_warn "APIM VNet type: ${APIM_VNET_TYPE}"
  log_warn ""
  log_warn "Private endpoints are typically used with Internal mode APIM"
  log_warn "For External mode APIM, the gateway is already publicly accessible"
  log_warn ""
  read -r -p "Continue anyway? (y/N): " continue_anyway
  continue_anyway=${continue_anyway:-n}

  if [[ ! "${continue_anyway}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled"
    exit 0
  fi
fi

# Verify VNet exists
log_step "Verifying VNet..."
if ! VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "VNet '${VNET_NAME}' not found"
  exit 1
fi

# Verify subnet exists
# shellcheck disable=SC2034
if ! SUBNET_ID=$(az network vnet subnet show \
  --name "${PE_SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "Subnet '${PE_SUBNET_NAME}' not found in VNet '${VNET_NAME}'"
  exit 1
fi

log_info "VNet and subnet verified"

# Check if private endpoint already exists
log_step "Checking for existing private endpoint..."
if az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "Private endpoint '${PE_NAME}' already exists"
  log_info "Skipping creation"

  # Get private IP
  PRIVATE_IP=$(az network private-endpoint show \
    --name "${PE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "customDnsConfigs[0].ipAddresses[0]" -o tsv 2>/dev/null || echo "Not found")

  log_info ""
  log_info "Existing Private Endpoint:"
  log_info "  Name: ${PE_NAME}"
  log_info "  Private IP: ${PRIVATE_IP}"
  log_info ""
  exit 0
fi

# Create private endpoint
log_step "Creating private endpoint for APIM..."
log_info "This may take a few minutes..."

az network private-endpoint create \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --vnet-name "${VNET_NAME}" \
  --subnet "${PE_SUBNET_NAME}" \
  --private-connection-resource-id "${APIM_ID}" \
  --group-id "Gateway" \
  --connection-name "${PE_NAME}-connection" \
  --output none

log_info "✓ Private endpoint created: ${PE_NAME}"

# Create or update private DNS zone
log_step "Configuring private DNS zone..."
readonly DNS_ZONE_NAME="privatelink.azure-api.net"

if ! az network private-dns zone show \
  --name "${DNS_ZONE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating private DNS zone: ${DNS_ZONE_NAME}"
  az network private-dns zone create \
    --name "${DNS_ZONE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output none

  log_info "Linking DNS zone to VNet..."
  az network private-dns link vnet create \
    --name "${VNET_NAME}-link" \
    --resource-group "${RESOURCE_GROUP}" \
    --zone-name "${DNS_ZONE_NAME}" \
    --virtual-network "${VNET_ID}" \
    --registration-enabled false \
    --output none
else
  log_info "Private DNS zone already exists: ${DNS_ZONE_NAME}"
fi

# Create DNS zone group (auto-creates A record)
log_step "Creating DNS zone group..."
az network private-endpoint dns-zone-group create \
  --name "default" \
  --endpoint-name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --private-dns-zone "${DNS_ZONE_NAME}" \
  --zone-name "apim-zone" \
  --output none

log_info "✓ DNS zone group created"

# Get private endpoint details
PRIVATE_IP=$(az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

PRIVATE_FQDN=$(az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDnsConfigs[0].fqdn" -o tsv)

log_info ""
log_info "✓ APIM Private Endpoint Created!"
log_info ""
log_info "========================================="
log_info "Private Endpoint Details"
log_info "========================================="
log_info "APIM Name:        ${APIM_NAME}"
log_info "VNet Mode:        ${APIM_VNET_TYPE}"
log_info "Private Endpoint: ${PE_NAME}"
log_info "Private IP:       ${PRIVATE_IP}"
log_info "Private FQDN:     ${PRIVATE_FQDN}"
log_info "DNS Zone:         ${DNS_ZONE_NAME}"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure APIM backend: ./31-apim-backend.sh"
log_info "  2. Apply APIM policies: ./32-apim-policies.sh"
log_info "  3. Configure AppGW routing: ./55-add-path-based-routing.sh"
log_info ""
