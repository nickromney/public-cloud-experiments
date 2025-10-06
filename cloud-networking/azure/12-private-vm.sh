#!/usr/bin/env bash
#
# Deploy VM to private subnet (subnet4)
# Demonstrates: VM in private subnet cannot reach internet
# - subnet4: 10.0.40.0/24, defaultOutboundAccess: false
# - No NAT Gateway attached
# - No public IP assigned to VM

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

log_info "Deploying VM to private subnet (subnet4)"
log_info ""
log_info "This VM will demonstrate:"
log_info "  • Private subnet with defaultOutboundAccess: false"
log_info "  • Cannot reach internet"
log_info "  • Can communicate with other subnets (based on NSG rules)"
log_info ""

# Deploy VM to subnet4 (private subnet)
SUBNET_NAME=snet-subnet4 \
VM_NAME=vm-private \
VM_SIZE=Standard_B1s \
"${SCRIPT_DIR}/resource-virtual-machine.sh"

log_info ""
log_info "Done! Private VM deployed"
log_info ""
log_info "Next steps:"
log_info "1. Run 13-private-vm-tests.sh to verify behavior"
log_info "2. The VM should:"
log_info "   ✓ Be able to reach containers/VMs in other subnets"
log_info "   ✗ NOT be able to reach internet (curl google.com should fail)"
