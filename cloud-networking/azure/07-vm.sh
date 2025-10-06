#!/usr/bin/env bash
#
# Deploy virtual machine to subnet 3 with nftables firewall
# - VM in subnet3 (10.0.30.0/24)
# - Configured with nftables rules via cloud-init

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly LOCATION="${LOCATION:-eastus2}"
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

log_info "Deploying virtual machine with nftables firewall"
log_info ""

# Deploy VM to subnet3 with nftables cloud-init
log_info "Deploying to snet-subnet3 (private subnet)..."
SUBNET_NAME=snet-subnet3 \
VM_NAME=vm-firewall \
CUSTOM_DATA="${SCRIPT_DIR}/nftables-config.yaml" \
"${SCRIPT_DIR}/resource-virtual-machine.sh"

log_info ""
log_info "Done! Virtual machine deployed"
log_info ""
log_info "The VM has been configured with nftables rules:"
log_info "  - Receives traffic from subnets 1, 3, 4"
log_info "  - Drops traffic from subnet 2"
log_info "  - Allows subnet3 -> subnet2 forwarding"
log_info ""
log_info "To verify nftables rules, SSH into the VM and run:"
log_info "  sudo nft list ruleset"
