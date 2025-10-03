#!/usr/bin/env bash
#
# Create simple Azure VNET with subnet and NSG
# - Virtual Network with configurable address space (default: 10.0.0.0/16)
# - Subnet with configurable CIDR (default: 10.1.0.0/24)
# - Network Security Group allowing inbound HTTPS (443) from anywhere
#
# Usage:
#   ./azure-simple-vnet.sh
#   LOCATION=westus2 ./azure-simple-vnet.sh
#   VNET_PREFIX=10.200.0.0/16 SUBNET_PREFIX=10.200.1.0/24 ./azure-simple-vnet.sh

set -euo pipefail

# Configuration parameters
readonly LOCATION="${LOCATION:-eastus2}"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly VNET_PREFIX="${VNET_PREFIX:-10.0.0.0/16}"
readonly SUBNET_NAME="${SUBNET_NAME:-snet-default}"
readonly SUBNET_PREFIX="${SUBNET_PREFIX:-10.1.0.0/24}"
readonly NSG_NAME="${NSG_NAME:-nsg-simple}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

function log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

function log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

function log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

function echo_usage() {
  echo "Usage:"
  echo "  ./azure-simple-vnet.sh"
  echo "  LOCATION=eastus ./azure-simple-vnet.sh"
  echo ""
  echo "Optional Environment Variables:"
  echo "  LOCATION          Azure region (default: eastus2)"
  echo "  RESOURCE_GROUP    Resource group name (default: rg-simple-vnet)"
  echo "  VNET_NAME         Virtual Network name (default: vnet-simple)"
  echo "  VNET_PREFIX       VNET address space (default: 10.0.0.0/16)"
  echo "  SUBNET_NAME       Subnet name (default: snet-default)"
  echo "  SUBNET_PREFIX     Subnet address space (default: 10.1.0.0/24)"
  echo "  NSG_NAME          Network Security Group name (default: nsg-simple)"
  echo ""
  echo "Examples:"
  echo "  ./azure-simple-vnet.sh"
  echo "  LOCATION=westus2 RESOURCE_GROUP=my-rg ./azure-simple-vnet.sh"
  echo "  VNET_PREFIX=10.200.0.0/16 SUBNET_PREFIX=10.200.1.0/24 ./azure-simple-vnet.sh"
}

# Check if script is called with -h or --help
if [[ "$#" -gt 0 ]]; then
  case "$1" in
  -h | --help)
    echo_usage
    exit 0
    ;;
  *)
    log_error "Unknown option: $1"
    echo_usage
    exit 1
    ;;
  esac
fi

# Check Azure CLI is installed
if ! command -v az &>/dev/null; then
  log_error "Azure CLI is not installed. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

# Check Azure CLI is logged in
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login' first"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  VNET Name: ${VNET_NAME}"
log_info "  VNET Prefix: ${VNET_PREFIX}"
log_info "  Subnet Name: ${SUBNET_NAME}"
log_info "  Subnet Prefix: ${SUBNET_PREFIX}"
log_info "  NSG Name: ${NSG_NAME}"
log_info ""

# Create or verify resource group
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating resource group ${RESOURCE_GROUP} in ${LOCATION}"
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
  log_info "Resource group ${RESOURCE_GROUP} created"
else
  log_info "Resource group ${RESOURCE_GROUP} already exists"
fi

# Create or verify Network Security Group
if ! az network nsg show \
  --name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating Network Security Group ${NSG_NAME}"
  az network nsg create \
    --name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
  log_info "Network Security Group ${NSG_NAME} created"
else
  log_info "Network Security Group ${NSG_NAME} already exists"
fi

# Create NSG rule to allow HTTPS (443) from anywhere
if ! az network nsg rule show \
  --name "AllowHTTPS" \
  --nsg-name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating NSG rule to allow inbound HTTPS (443) from anywhere"
  az network nsg rule create \
    --name "AllowHTTPS" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges 443 \
    --description "Allow HTTPS from anywhere" \
    --output none
  log_info "NSG rule AllowHTTPS created"
else
  log_info "NSG rule AllowHTTPS already exists"
fi

# Create or verify Virtual Network
if ! az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating Virtual Network ${VNET_NAME} with address prefix ${VNET_PREFIX}"
  az network vnet create \
    --name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --address-prefixes "${VNET_PREFIX}" \
    --output none
  log_info "Virtual Network ${VNET_NAME} created"
else
  log_info "Virtual Network ${VNET_NAME} already exists"
fi

# Create or verify Subnet
if ! az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating subnet ${SUBNET_NAME} with address prefix ${SUBNET_PREFIX}"
  az network vnet subnet create \
    --name "${SUBNET_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --address-prefix "${SUBNET_PREFIX}" \
    --network-security-group "${NSG_NAME}" \
    --output none
  log_info "Subnet ${SUBNET_NAME} created and associated with NSG ${NSG_NAME}"
else
  log_info "Subnet ${SUBNET_NAME} already exists"
fi

# Display summary
log_info ""
log_info "=== Networking Summary ==="
VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id \
  --output tsv)
log_info "VNET ID: ${VNET_ID}"

SUBNET_ID=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id \
  --output tsv)
log_info "Subnet ID: ${SUBNET_ID}"

NSG_ID=$(az network nsg show \
  --name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id \
  --output tsv)
log_info "NSG ID: ${NSG_ID}"

log_info ""
log_info "=== Resources Created ==="
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  VNET: ${VNET_NAME} (${VNET_PREFIX})"
log_info "  Subnet: ${SUBNET_NAME} (${SUBNET_PREFIX})"
log_info "  NSG: ${NSG_NAME} (allows HTTPS/443 from anywhere)"
log_info ""
log_info "Done!"
