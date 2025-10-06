#!/usr/bin/env bash
#
# Deploy container instances with custom nginx pages
# Each container displays its subnet and IP information
# - aci-custom-subnet1: nginx in subnet1
# - aci-custom-subnet2: nginx in subnet2

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"

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
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv 2>/dev/null || echo "")
  if [[ -z "${LOCATION}" ]]; then
    log_error "Could not detect location from resource group ${RESOURCE_GROUP}"
    exit 1
  fi
fi
readonly LOCATION

log_info "Deploying container instances with custom nginx pages"
log_info ""

# Deploy to subnet1
log_info "Deploying to snet-subnet1..."
SUBNET_NAME=snet-subnet1 \
CONTAINER_NAME=aci-custom-subnet1 \
"${SCRIPT_DIR}/resource-container-custom.sh"

# Deploy to subnet2
log_info ""
log_info "Deploying to snet-subnet2..."
SUBNET_NAME=snet-subnet2 \
CONTAINER_NAME=aci-custom-subnet2 \
"${SCRIPT_DIR}/resource-container-custom.sh"

log_info ""
log_info "Done! Custom container instances deployed"
log_info ""
log_info "Test the custom pages:"
log_info "1. Get container IPs:"
log_info "   az container show -n aci-custom-subnet1 -g ${RESOURCE_GROUP} --query ipAddress.ip -o tsv"
log_info "   az container show -n aci-custom-subnet2 -g ${RESOURCE_GROUP} --query ipAddress.ip -o tsv"
log_info ""
log_info "2. Access from another container/VM:"
log_info "   curl http://<container-ip>"
log_info "   # You'll see the subnet name and IP displayed on the welcome page"
