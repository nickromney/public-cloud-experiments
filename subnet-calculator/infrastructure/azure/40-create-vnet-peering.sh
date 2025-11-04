#!/usr/bin/env bash
#
# 40-create-vnet-peering.sh - Create VNet Peering between two VNets
#
# This script creates bi-directional VNet peering to enable communication
# between APIM VNets (Stack 17/18) and Stack 16's VNet.
#
# Peering enables:
# - Stack 17/18 APIM → Stack 16 private Function App
# - Stack 18 only: Stack 16 AppGW → Stack 18 private APIM
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   SOURCE_VNET="vnet-subnet-calc-apim-external" \
#   DEST_VNET="vnet-subnet-calc-private" \
#   ./40-create-vnet-peering.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP  - Resource group name (both VNets must be in same RG)
#   SOURCE_VNET     - Source VNet name (e.g., vnet-subnet-calc-apim-external)
#   DEST_VNET       - Destination VNet name (e.g., vnet-subnet-calc-private)
#
# Exit Codes:
#   0 - Success (peering created or already exists)
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

if [[ -z "${SOURCE_VNET:-}" ]]; then
  log_error "SOURCE_VNET environment variable is required"
  exit 1
fi

if [[ -z "${DEST_VNET:-}" ]]; then
  log_error "DEST_VNET environment variable is required"
  exit 1
fi

log_info ""
log_info "======================================="
log_info "VNet Peering Configuration"
log_info "======================================="
log_info "Resource Group:  ${RESOURCE_GROUP}"
log_info "Source VNet:     ${SOURCE_VNET}"
log_info "Destination VNet: ${DEST_VNET}"
log_info ""

# Check if VNets exist
log_step "Validating VNets..."

if ! az network vnet show --name "${SOURCE_VNET}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Source VNet '${SOURCE_VNET}' not found"
  exit 1
fi

if ! az network vnet show --name "${DEST_VNET}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Destination VNet '${DEST_VNET}' not found"
  exit 1
fi

log_info "✓ Both VNets exist"

# Get VNet resource IDs
SOURCE_VNET_ID=$(az network vnet show \
  --name "${SOURCE_VNET}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "id" -o tsv)

DEST_VNET_ID=$(az network vnet show \
  --name "${DEST_VNET}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "id" -o tsv)

# Peering names
PEERING_NAME_1="${SOURCE_VNET}-to-${DEST_VNET}"
PEERING_NAME_2="${DEST_VNET}-to-${SOURCE_VNET}"

# Check if peering already exists (source to dest)
log_step "Checking existing peering connections..."

if az network vnet peering show \
  --name "${PEERING_NAME_1}" \
  --vnet-name "${SOURCE_VNET}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Peering '${PEERING_NAME_1}' already exists"
  PEERING_1_EXISTS=true
else
  PEERING_1_EXISTS=false
fi

# Check if reverse peering exists (dest to source)
if az network vnet peering show \
  --name "${PEERING_NAME_2}" \
  --vnet-name "${DEST_VNET}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Peering '${PEERING_NAME_2}' already exists"
  PEERING_2_EXISTS=true
else
  PEERING_2_EXISTS=false
fi

if [[ "${PEERING_1_EXISTS}" == "true" ]] && [[ "${PEERING_2_EXISTS}" == "true" ]]; then
  log_info "✓ Bi-directional peering already configured"
  exit 0
fi

# Create peering (source to dest)
if [[ "${PEERING_1_EXISTS}" == "false" ]]; then
  log_step "Creating peering: ${SOURCE_VNET} → ${DEST_VNET}"
  az network vnet peering create \
    --name "${PEERING_NAME_1}" \
    --vnet-name "${SOURCE_VNET}" \
    --resource-group "${RESOURCE_GROUP}" \
    --remote-vnet "${DEST_VNET_ID}" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --output none

  log_info "✓ Peering created: ${PEERING_NAME_1}"
fi

# Create reverse peering (dest to source)
if [[ "${PEERING_2_EXISTS}" == "false" ]]; then
  log_step "Creating peering: ${DEST_VNET} → ${SOURCE_VNET}"
  az network vnet peering create \
    --name "${PEERING_NAME_2}" \
    --vnet-name "${DEST_VNET}" \
    --resource-group "${RESOURCE_GROUP}" \
    --remote-vnet "${SOURCE_VNET_ID}" \
    --allow-vnet-access \
    --allow-forwarded-traffic \
    --output none

  log_info "✓ Peering created: ${PEERING_NAME_2}"
fi

log_info ""
log_info "======================================="
log_info "VNet Peering Complete"
log_info "======================================="
log_info "Peering Name 1: ${PEERING_NAME_1}"
log_info "Peering Name 2: ${PEERING_NAME_2}"
log_info "Status:         Connected"
log_info ""
log_info "Resources in ${SOURCE_VNET} can now communicate with"
log_info "resources in ${DEST_VNET} and vice versa."
log_info ""
