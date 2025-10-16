#!/usr/bin/env bash
#
# Create Azure Virtual Network infrastructure for subnet calculator
# - VNet with 10.0.0.0/16 address space
# - Function integration subnet (10.0.1.0/28) with Microsoft.Web/serverFarms delegation
# - Private endpoints subnet (10.0.2.0/28) for future use
# - Network Security Group attached to function subnet
# - Works in sandbox environments (pre-existing resource group)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Source selection utilities
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
    log_error "Create one with: az group create --name rg-subnet-calc --location eastus"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    RG_LOCATION=$(az group list --query "[0].location" -o tsv)
    log_info "Found single resource group: ${RESOURCE_GROUP} (${RG_LOCATION})"
    log_info "This appears to be a sandbox or constrained environment."
    read -r -p "Use this resource group? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Check for existing VNets (informational only - multiple allowed)
if [[ -z "${VNET_NAME:-}" ]]; then
  VNET_COUNT=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${VNET_COUNT}" -eq 1 ]]; then
    EXISTING_VNET_NAME=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_VNET_SPACE=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[0].addressSpace.addressPrefixes[0]" -o tsv)

    log_info "Found existing VNet: ${EXISTING_VNET_NAME}"
    log_info "  Address space: ${EXISTING_VNET_SPACE}"
    log_info ""
    log_info "Note: Multiple VNets are allowed in the same resource group."
    log_info "      Useful for network isolation (dev/test, different apps, etc.)"
    log_info ""
    read -r -p "Use existing VNet? (Y/n): " use_existing
    use_existing=${use_existing:-y}

    if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
      VNET_NAME="${EXISTING_VNET_NAME}"

      log_info ""
      log_info "✓ Using existing VNet"
      log_info ""
      log_info "VNet Details:"
      log_info "  Name: ${VNET_NAME}"
      log_info "  Address space: ${EXISTING_VNET_SPACE}"
      log_info ""
      log_info "Subnets:"
      az network vnet subnet list --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" \
        --query "[].[name,addressPrefix]" -o tsv | awk '{printf "  - %s (%s)\n", $1, $2}'
      log_info ""
      log_info "Next steps:"
      log_info "  1. Integrate Function with VNet: ./14-configure-function-vnet-integration.sh"
      exit 0
    else
      log_info "Creating new VNet alongside existing one..."
    fi
  elif [[ "${VNET_COUNT}" -gt 1 ]]; then
    log_info "Found ${VNET_COUNT} existing VNets in ${RESOURCE_GROUP}:"
    az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[].[name,addressSpace.addressPrefixes[0]]" -o tsv | \
      awk '{printf "  - %s (%s)\n", $1, $2}'
    log_info ""
    log_info "Multiple VNets are normal for complex network designs."
    log_info "Creating new VNet with unique name..."
  fi
fi

# Configuration with defaults
readonly VNET_NAME="${VNET_NAME:-vnet-subnet-calc}"
readonly VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.0.0.0/16}"
readonly SUBNET_FUNCTION_NAME="${SUBNET_FUNCTION_NAME:-snet-function-integration}"
readonly SUBNET_FUNCTION_PREFIX="${SUBNET_FUNCTION_PREFIX:-10.0.1.0/28}"
readonly SUBNET_PE_NAME="${SUBNET_PE_NAME:-snet-private-endpoints}"
readonly SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.0.2.0/28}"
readonly NSG_NAME="${NSG_NAME:-nsg-subnet-calc}"

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected location from resource group: ${LOCATION}"
  else
    log_error "Resource group ${RESOURCE_GROUP} not found and LOCATION not set"
    log_error "Either create the resource group first or set LOCATION environment variable"
    exit 1
  fi
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  VNet Name: ${VNET_NAME}"
log_info "  VNet Address Space: ${VNET_ADDRESS_SPACE}"
log_info "  Function Subnet: ${SUBNET_FUNCTION_NAME} (${SUBNET_FUNCTION_PREFIX})"
log_info "  Private Endpoints Subnet: ${SUBNET_PE_NAME} (${SUBNET_PE_PREFIX})"
log_info "  NSG Name: ${NSG_NAME}"

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group ${RESOURCE_GROUP} not found"
  log_error "Create the resource group first or set correct RESOURCE_GROUP variable"
  exit 1
fi

# Check if VNet already exists
if az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "VNet ${VNET_NAME} already exists"
else
  # Create VNet
  log_info "Creating VNet ${VNET_NAME}..."
  az network vnet create \
    --name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --address-prefix "${VNET_ADDRESS_SPACE}" \
    --output none

  log_info "VNet created successfully"
fi

# Check if Function integration subnet exists
if az network vnet subnet show \
  --name "${SUBNET_FUNCTION_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Function integration subnet ${SUBNET_FUNCTION_NAME} already exists"

  # Verify delegation
  DELEGATION=$(az network vnet subnet show \
    --name "${SUBNET_FUNCTION_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "delegations[0].serviceName" \
    -o tsv 2>/dev/null || echo "")

  if [[ "${DELEGATION}" != "Microsoft.Web/serverFarms" ]]; then
    log_warn "Function subnet exists but delegation is '${DELEGATION}', expected 'Microsoft.Web/serverFarms'"
    log_warn "You may need to delete and recreate the subnet if delegation is incorrect"
  fi
else
  # Create Function integration subnet with delegation
  log_info "Creating Function integration subnet ${SUBNET_FUNCTION_NAME}..."
  az network vnet subnet create \
    --name "${SUBNET_FUNCTION_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --address-prefix "${SUBNET_FUNCTION_PREFIX}" \
    --delegations "Microsoft.Web/serverFarms" \
    --output none

  log_info "Function integration subnet created with Microsoft.Web/serverFarms delegation"
fi

# Check if Private Endpoints subnet exists
if az network vnet subnet show \
  --name "${SUBNET_PE_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Private Endpoints subnet ${SUBNET_PE_NAME} already exists"
else
  # Create Private Endpoints subnet (no delegation)
  log_info "Creating Private Endpoints subnet ${SUBNET_PE_NAME}..."
  az network vnet subnet create \
    --name "${SUBNET_PE_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --address-prefix "${SUBNET_PE_PREFIX}" \
    --output none

  log_info "Private Endpoints subnet created"
fi

# Check if NSG already exists
if az network nsg show \
  --name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "NSG ${NSG_NAME} already exists"
else
  # Create Network Security Group
  log_info "Creating Network Security Group ${NSG_NAME}..."
  az network nsg create \
    --name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none

  log_info "NSG created successfully"

  # Add outbound rule for HTTPS (443)
  log_info "Adding NSG rule: Allow outbound HTTPS (443)..."
  az network nsg rule create \
    --name "AllowOutboundHTTPS" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority 100 \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --destination-port-ranges 443 \
    --source-address-prefixes "*" \
    --destination-address-prefixes "Internet" \
    --description "Allow outbound HTTPS to internet" \
    --output none

  # Add outbound rule for HTTP (80)
  log_info "Adding NSG rule: Allow outbound HTTP (80)..."
  az network nsg rule create \
    --name "AllowOutboundHTTP" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority 110 \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --destination-port-ranges 80 \
    --source-address-prefixes "*" \
    --destination-address-prefixes "Internet" \
    --description "Allow outbound HTTP to internet" \
    --output none

  # Add outbound rule for Azure services
  log_info "Adding NSG rule: Allow outbound to Azure services..."
  az network nsg rule create \
    --name "AllowOutboundAzureServices" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority 120 \
    --direction Outbound \
    --access Allow \
    --protocol "*" \
    --destination-port-ranges "*" \
    --source-address-prefixes "*" \
    --destination-address-prefixes "AzureCloud" \
    --description "Allow outbound to Azure services" \
    --output none

  # Add inbound deny rule (Function doesn't accept inbound from VNet)
  log_info "Adding NSG rule: Deny all inbound..."
  az network nsg rule create \
    --name "DenyAllInbound" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority 4096 \
    --direction Inbound \
    --access Deny \
    --protocol "*" \
    --destination-port-ranges "*" \
    --source-address-prefixes "*" \
    --destination-address-prefixes "*" \
    --description "Deny all inbound traffic (Function doesn't accept inbound from VNet)" \
    --output none

  log_info "NSG rules created successfully"
fi

# Attach NSG to Function integration subnet
log_info "Attaching NSG to Function integration subnet..."
az network vnet subnet update \
  --name "${SUBNET_FUNCTION_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --network-security-group "${NSG_NAME}" \
  --output none

log_info "NSG attached to subnet successfully"

# Get resource IDs for output
VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

SUBNET_FUNCTION_ID=$(az network vnet subnet show \
  --name "${SUBNET_FUNCTION_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

SUBNET_PE_ID=$(az network vnet subnet show \
  --name "${SUBNET_PE_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

NSG_ID=$(az network nsg show \
  --name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

# Verify delegation
DELEGATION=$(az network vnet subnet show \
  --name "${SUBNET_FUNCTION_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "delegations[0].serviceName" \
  -o tsv)

log_info ""
log_info "========================================="
log_info "VNet Infrastructure created successfully!"
log_info "========================================="
log_info ""
log_info "VNet: ${VNET_NAME}"
log_info "  Address space: ${VNET_ADDRESS_SPACE}"
log_info "  Location: ${LOCATION}"
log_info "  Resource ID: ${VNET_ID}"
log_info ""
log_info "Subnets:"
log_info "  ${SUBNET_FUNCTION_NAME} (${SUBNET_FUNCTION_PREFIX}) - 16 addresses"
log_info "    Delegated to: ${DELEGATION}"
log_info "    Resource ID: ${SUBNET_FUNCTION_ID}"
log_info ""
log_info "  ${SUBNET_PE_NAME} (${SUBNET_PE_PREFIX}) - 16 addresses"
log_info "    No delegation (reserved for Private Endpoints)"
log_info "    Resource ID: ${SUBNET_PE_ID}"
log_info ""
log_info "NSG: ${NSG_NAME}"
log_info "  Attached to: ${SUBNET_FUNCTION_NAME}"
log_info "  Resource ID: ${NSG_ID}"
log_info ""
log_info "Next steps:"
log_info "  1. Create App Service Plan: ./12-create-app-service-plan.sh"
log_info "  2. Migrate Function to ASP: ./13-migrate-function-to-app-service-plan.sh"
log_info ""
log_info "To verify the configuration, run:"
log_info "  az network vnet show --name ${VNET_NAME} --resource-group ${RESOURCE_GROUP} --query '{name:name,addressSpace:addressSpace,subnets:subnets[].name}' -o table"
