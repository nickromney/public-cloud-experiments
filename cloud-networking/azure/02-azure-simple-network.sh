#!/usr/bin/env bash
#
# Create simple Azure network with two subnets
# - VNET: 10.0.0.0/16
# - Subnet 1: 10.0.10.0/24
# - Subnet 2: 10.0.20.0/24
# - NSG: Allow HTTPS inbound, TCP/ICMP between subnets

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"
readonly SUBNET1_NAME="${SUBNET1_NAME:-snet-subnet1}"
readonly SUBNET1_PREFIX="${SUBNET1_PREFIX:-10.0.10.0/24}"
readonly SUBNET2_NAME="${SUBNET2_NAME:-snet-subnet2}"
readonly SUBNET2_PREFIX="${SUBNET2_PREFIX:-10.0.20.0/24}"
readonly SUBNET3_NAME="${SUBNET3_NAME:-snet-subnet3}"
readonly SUBNET3_PREFIX="${SUBNET3_PREFIX:-10.0.30.0/24}"
readonly SUBNET4_NAME="${SUBNET4_NAME:-snet-subnet4}"
readonly SUBNET4_PREFIX="${SUBNET4_PREFIX:-10.0.40.0/24}"
readonly NSG_NAME="${NSG_NAME:-nsg-simple}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected location from resource group: ${LOCATION}"
  else
    log_error "Resource group ${RESOURCE_GROUP} not found and LOCATION not set"
    exit 1
  fi
fi
readonly LOCATION

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  VNET: ${VNET_NAME} (${VNET_PREFIX})"
log_info "  Subnet 1: ${SUBNET1_NAME} (${SUBNET1_PREFIX}) - Public"
log_info "  Subnet 2: ${SUBNET2_NAME} (${SUBNET2_PREFIX}) - Public"
log_info "  Subnet 3: ${SUBNET3_NAME} (${SUBNET3_PREFIX}) - Public (NVA/firewall)"
log_info "  Subnet 4: ${SUBNET4_NAME} (${SUBNET4_PREFIX}) - Private"
log_info "  NSG: ${NSG_NAME}"
log_info ""

# Create or verify resource group
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating resource group ${RESOURCE_GROUP}"
  az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none
else
  log_info "Resource group ${RESOURCE_GROUP} exists"
fi

# Create VNET
if ! az network vnet show --name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating VNET ${VNET_NAME}"
  "${SCRIPT_DIR}/resource-vnet.sh" "${RESOURCE_GROUP}" "${VNET_NAME}" "${VNET_PREFIX}" "${LOCATION}"
else
  log_info "VNET ${VNET_NAME} exists"
fi

# Create NSG
if ! az network nsg show --name "${NSG_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating NSG ${NSG_NAME}"
  "${SCRIPT_DIR}/resource-nsg.sh" "${RESOURCE_GROUP}" "${NSG_NAME}" "${LOCATION}"
else
  log_info "NSG ${NSG_NAME} exists"
fi

# Create Subnet 1
if ! az network vnet subnet show --name "${SUBNET1_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating subnet ${SUBNET1_NAME}"
  "${SCRIPT_DIR}/resource-subnet.sh" "${RESOURCE_GROUP}" "${VNET_NAME}" "${SUBNET1_NAME}" "${SUBNET1_PREFIX}" "${NSG_NAME}"
else
  log_info "Subnet ${SUBNET1_NAME} exists"
fi

# Create Subnet 2 (public)
if ! az network vnet subnet show --name "${SUBNET2_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating subnet ${SUBNET2_NAME}"
  "${SCRIPT_DIR}/resource-subnet.sh" "${RESOURCE_GROUP}" "${VNET_NAME}" "${SUBNET2_NAME}" "${SUBNET2_PREFIX}" "${NSG_NAME}"
else
  log_info "Subnet ${SUBNET2_NAME} exists"
fi

# Create Subnet 3 (public - for NVA/firewall)
if ! az network vnet subnet show --name "${SUBNET3_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating public subnet ${SUBNET3_NAME} (for NVA/firewall)"
  "${SCRIPT_DIR}/resource-subnet.sh" "${RESOURCE_GROUP}" "${VNET_NAME}" "${SUBNET3_NAME}" "${SUBNET3_PREFIX}" "${NSG_NAME}"
else
  log_info "Subnet ${SUBNET3_NAME} exists"
fi

# Create Subnet 4 (private - no default outbound access)
if ! az network vnet subnet show --name "${SUBNET4_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating private subnet ${SUBNET4_NAME} (no default outbound access)"
  "${SCRIPT_DIR}/resource-subnet.sh" "${RESOURCE_GROUP}" "${VNET_NAME}" "${SUBNET4_NAME}" "${SUBNET4_PREFIX}" "${NSG_NAME}" "true"
else
  log_info "Subnet ${SUBNET4_NAME} exists"
fi

log_info ""
log_info "Done! Network created successfully"
