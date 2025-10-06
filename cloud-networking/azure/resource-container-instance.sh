#!/usr/bin/env bash
#
# Deploy Azure Container Instance into a subnet
# Uses nginx image for simple HTTP server

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly SUBNET_NAME="${SUBNET_NAME:-snet-subnet1}"
readonly CONTAINER_NAME="${CONTAINER_NAME:-aci-test}"
readonly IMAGE="${IMAGE:-mcr.microsoft.com/oss/nginx/nginx:1.9.15-alpine}"

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
log_info "  Container: ${CONTAINER_NAME}"
log_info "  Image: ${IMAGE}"
log_info ""

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

# Create container instance
log_info "Creating container instance ${CONTAINER_NAME}..."
az container create \
  --name "${CONTAINER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --image "${IMAGE}" \
  --vnet "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --location "${LOCATION}" \
  --os-type Linux \
  --cpu 1 \
  --memory 1 \
  --output none

log_info "Container instance created successfully"
log_info ""

# Get container details
CONTAINER_IP=$(az container show \
  --name "${CONTAINER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv)

log_info "Container Details:"
log_info "  Name: ${CONTAINER_NAME}"
log_info "  Private IP: ${CONTAINER_IP}"
log_info "  Image: ${IMAGE}"
log_info ""
log_info "To test connectivity from another subnet:"
log_info "  curl http://${CONTAINER_IP}"
