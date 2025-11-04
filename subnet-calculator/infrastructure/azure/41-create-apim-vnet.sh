#!/usr/bin/env bash
#
# 41-create-apim-vnet.sh - Create VNet for Azure API Management
#
# This script creates a dedicated virtual network for APIM deployment.
# Supports both External and Internal APIM modes with appropriate subnet sizing.
#
# APIM External Mode:
#   - APIM gateway is public, can reach private backends
#   - Requires subnet for APIM only
#   - Peers to Stack 16 VNet to reach private Function App
#
# APIM Internal Mode:
#   - APIM gateway is private (VNet only)
#   - Requires subnet for APIM only
#   - Peers to Stack 16 VNet to reach AppGW (for routing) and private Function App
#
# Usage:
#   # External mode (Stack 17)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-subnet-calc-apim-external" \
#   VNET_MODE="External" \
#   ./41-create-apim-vnet.sh
#
#   # Internal mode (Stack 18)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-subnet-calc-apim-internal" \
#   VNET_MODE="Internal" \
#   ./41-create-apim-vnet.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP  - Resource group name
#   VNET_NAME       - Virtual network name
#   VNET_MODE       - "External" or "Internal"
#
# Optional Environment Variables:
#   LOCATION        - Azure region (auto-detected from resource group)
#   VNET_PREFIX     - VNet address space (default: 10.200.0.0/16 for External, 10.201.0.0/16 for Internal)
#   APIM_SUBNET_PREFIX - APIM subnet CIDR (default: 10.x.0.0/27)
#
# Exit Codes:
#   0 - Success (VNet and subnets created)
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

if [[ -z "${VNET_MODE:-}" ]]; then
  log_error "VNET_MODE environment variable is required (External or Internal)"
  exit 1
fi

# Validate VNET_MODE
if [[ "${VNET_MODE}" != "External" && "${VNET_MODE}" != "Internal" ]]; then
  log_error "VNET_MODE must be 'External' or 'Internal', got: ${VNET_MODE}"
  exit 1
fi

# Auto-detect location from resource group if not provided
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Auto-detected location: ${LOCATION}"
fi

# Set defaults based on mode
if [[ "${VNET_MODE}" == "External" ]]; then
  VNET_PREFIX="${VNET_PREFIX:-10.200.0.0/16}"
  APIM_SUBNET_PREFIX="${APIM_SUBNET_PREFIX:-10.200.0.0/27}"
else
  VNET_PREFIX="${VNET_PREFIX:-10.201.0.0/16}"
  APIM_SUBNET_PREFIX="${APIM_SUBNET_PREFIX:-10.201.0.0/27}"
fi

log_info ""
log_info "======================================="
log_info "APIM VNet Creation (${VNET_MODE} Mode)"
log_info "======================================="
log_info "Resource Group:    ${RESOURCE_GROUP}"
log_info "Location:          ${LOCATION}"
log_info "VNet Name:         ${VNET_NAME}"
log_info "VNet Mode:         ${VNET_MODE}"
log_info "VNet Address:      ${VNET_PREFIX}"
log_info "APIM Subnet:       ${APIM_SUBNET_PREFIX}"
log_info ""

# Check if VNet already exists
log_step "Checking if VNet already exists..."
if az network vnet show --resource-group "${RESOURCE_GROUP}" --name "${VNET_NAME}" &>/dev/null; then
  log_info "VNet '${VNET_NAME}' already exists"

  # Check if APIM subnet exists
  if az network vnet subnet show \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_NAME}" \
    --name "snet-apim" &>/dev/null; then
    log_info "✓ VNet and APIM subnet already configured"
    exit 0
  else
    log_error "VNet exists but APIM subnet is missing"
    exit 1
  fi
fi

# Create VNet
log_step "Creating VNet..."
az network vnet create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VNET_NAME}" \
  --location "${LOCATION}" \
  --address-prefix "${VNET_PREFIX}" \
  --output none

log_info "✓ VNet created"

# Create APIM subnet
log_step "Creating APIM subnet..."
az network vnet subnet create \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet-name "${VNET_NAME}" \
  --name "snet-apim" \
  --address-prefix "${APIM_SUBNET_PREFIX}" \
  --output none

log_info "✓ APIM subnet created"

log_info ""
log_info "======================================="
log_info "VNet Configuration Complete"
log_info "======================================="
log_info "VNet Name:     ${VNET_NAME}"
log_info "VNet Mode:     ${VNET_MODE}"
log_info "Subnets:"
log_info "  - snet-apim:   ${APIM_SUBNET_PREFIX}"
log_info ""
log_info "Next steps:"
log_info "  1. Create VNet peering to Stack 16 VNet"
log_info "  2. Create NSG for APIM subnet (42-create-apim-nsg.sh)"
log_info "  3. Deploy APIM instance (43-create-apim-vnet.sh)"
log_info ""
