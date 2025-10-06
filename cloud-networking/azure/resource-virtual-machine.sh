#!/usr/bin/env bash
#
# Deploy Azure Virtual Machine into a subnet
# Uses Ubuntu 24.04 LTS by default

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly SUBNET_NAME="${SUBNET_NAME:-snet-subnet1}"
readonly VM_NAME="${VM_NAME:-vm-test}"
readonly VM_SIZE="${VM_SIZE:-Standard_B2s}"
readonly IMAGE="${IMAGE:-Ubuntu2404}"  # Ubuntu 24.04 LTS
readonly ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
readonly CUSTOM_DATA="${CUSTOM_DATA:-}"  # Optional cloud-init script path
readonly ENABLE_IP_FORWARDING="${ENABLE_IP_FORWARDING:-false}"  # Enable IP forwarding on NIC
readonly CREATE_PUBLIC_IP="${CREATE_PUBLIC_IP:-false}"  # Create and attach public IP

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv 2>/dev/null || echo "")
  if [[ -z "${LOCATION}" ]]; then
    log_error "Could not detect location from resource group ${RESOURCE_GROUP}"
    exit 1
  fi
fi
readonly LOCATION

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  VNET: ${VNET_NAME}"
log_info "  Subnet: ${SUBNET_NAME}"
log_info "  VM: ${VM_NAME}"
log_info "  Size: ${VM_SIZE}"
log_info "  Image: ${IMAGE}"
log_info "  Admin User: ${ADMIN_USERNAME}"
if [[ -n "${CUSTOM_DATA}" ]]; then
  log_info "  Custom Data: ${CUSTOM_DATA}"
fi
if [[ "${ENABLE_IP_FORWARDING}" == "true" ]]; then
  log_info "  IP Forwarding: Enabled"
fi
if [[ "${CREATE_PUBLIC_IP}" == "true" ]]; then
  log_info "  Public IP: Will be created"
fi
log_info ""

# Create NIC name based on VM name
NIC_NAME="${VM_NAME}-nic"

# Get subnet ID
SUBNET_ID=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id \
  --output tsv)

if [[ -z "${SUBNET_ID}" ]]; then
  log_error "Subnet ${SUBNET_NAME} not found"
  exit 1
fi

log_info "Subnet ID: ${SUBNET_ID}"
log_info ""

# Create public IP if requested
PUBLIC_IP_NAME=""
if [[ "${CREATE_PUBLIC_IP}" == "true" ]]; then
  PUBLIC_IP_NAME="${VM_NAME}-pip"
  log_info "Creating public IP ${PUBLIC_IP_NAME}..."
  az network public-ip create \
    --name "${PUBLIC_IP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard \
    --allocation-method Static \
    --output none
  log_info "  Public IP created"
fi

# Create NIC
log_info "Creating network interface ${NIC_NAME}..."
NIC_ARGS=(
  --name "${NIC_NAME}"
  --resource-group "${RESOURCE_GROUP}"
  --location "${LOCATION}"
  --subnet "${SUBNET_ID}"
  --output none
)

# Add public IP if created
if [[ -n "${PUBLIC_IP_NAME}" ]]; then
  NIC_ARGS+=(--public-ip-address "${PUBLIC_IP_NAME}")
  log_info "  Attaching public IP ${PUBLIC_IP_NAME}"
fi

# Add IP forwarding if enabled
if [[ "${ENABLE_IP_FORWARDING}" == "true" ]]; then
  NIC_ARGS+=(--ip-forwarding true)
  log_info "  IP forwarding enabled on NIC"
fi

az network nic create "${NIC_ARGS[@]}"

# Build VM create command
VM_ARGS=(
  --name "${VM_NAME}"
  --resource-group "${RESOURCE_GROUP}"
  --location "${LOCATION}"
  --nics "${NIC_NAME}"
  --image "${IMAGE}"
  --size "${VM_SIZE}"
  --admin-username "${ADMIN_USERNAME}"
  --generate-ssh-keys
  --output none
)

# Add custom data if provided
if [[ -n "${CUSTOM_DATA}" ]] && [[ -f "${CUSTOM_DATA}" ]]; then
  VM_ARGS+=(--custom-data "${CUSTOM_DATA}")
fi

# Create VM
log_info "Creating virtual machine ${VM_NAME}..."
az vm create "${VM_ARGS[@]}"

log_info "Virtual machine created successfully"
log_info ""

# Get VM details
VM_PRIVATE_IP=$(az vm show \
  --name "${VM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --show-details \
  --query "privateIps" \
  --output tsv)

log_info "VM Details:"
log_info "  Name: ${VM_NAME}"
log_info "  Private IP: ${VM_PRIVATE_IP}"
log_info "  Size: ${VM_SIZE}"
log_info "  Image: ${IMAGE}"
log_info ""
log_info "To SSH into the VM from another subnet:"
log_info "  ssh ${ADMIN_USERNAME}@${VM_PRIVATE_IP}"
