#!/usr/bin/env bash
#
# Deploy container instances for network testing
# - aci-subnet1: nginx in public subnet (has internet)
# - aci-subnet2: nginx in private subnet (no internet, can reach subnet1)

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

log_info "Deploying container instances with custom nginx pages for network testing"
log_info ""

# Deploy to subnet1 (public)
log_info "Deploying to snet-subnet1 (public subnet)..."
SUBNET_NAME=snet-subnet1 \
CONTAINER_NAME=aci-subnet1 \
"${SCRIPT_DIR}/resource-container-custom.sh"

# Deploy to subnet2 (public)
log_info ""
log_info "Deploying to snet-subnet2 (public subnet)..."
SUBNET_NAME=snet-subnet2 \
CONTAINER_NAME=aci-subnet2 \
"${SCRIPT_DIR}/resource-container-custom.sh"

log_info ""
log_info "Done! Container instances deployed with custom nginx pages"
log_info ""
log_info "Custom pages show:"
log_info "  - Container hostname"
log_info "  - Private IP address"
log_info "  - Subnet CIDR"
log_info ""
log_info "Next steps to test connectivity:"
log_info "1. Get container IPs:"
log_info "   az container show -n aci-subnet1 -g ${RESOURCE_GROUP} --query ipAddress.ip -o tsv"
log_info "   az container show -n aci-subnet2 -g ${RESOURCE_GROUP} --query ipAddress.ip -o tsv"
log_info ""
log_info "2. Test with wget (from within containers):"
log_info "   az container exec -n aci-subnet2 -g ${RESOURCE_GROUP} --exec-command /bin/sh"
log_info "   # wget -q -O - http://<aci-subnet1-ip>  (should work - inter-subnet)"
log_info "   # wget -s http://google.com             (should work - both subnets public)"
log_info ""
log_info "3. Or run the automated tests:"
log_info "   ./06-container-tests.sh"
