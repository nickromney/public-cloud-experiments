#!/usr/bin/env bash
#
# Configure Network Virtual Appliance (NVA) routing
# Routes subnet4 traffic through subnet3 VM using User Defined Routes
#
# Architecture:
#   subnet4 (10.0.40.0/24) -> Route Table -> subnet3 VM (NVA) -> Internet

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly NVA_VM="${NVA_VM:-vm-firewall}"
readonly ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:-rt-subnet4-via-nva}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

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

log_info "========================================="
log_info "Configure NVA Routing"
log_info "========================================="
log_info ""

# Step 1: Get NVA VM private IP
log_info "Step 1: Getting NVA VM private IP..."
NVA_IP=$(az vm show \
  --name "${NVA_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --show-details \
  --query "privateIps" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "${NVA_IP}" ]]; then
  log_error "NVA VM ${NVA_VM} not found. Deploy with 07-vm.sh first"
  exit 1
fi

log_info "  NVA VM: ${NVA_VM}"
log_info "  NVA IP: ${NVA_IP}"
log_info ""

# Step 2: Enable IP forwarding on NVA VM NIC
log_info "Step 2: Enabling IP forwarding on NVA VM NIC..."
NIC_ID=$(az vm show \
  --name "${NVA_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "networkProfile.networkInterfaces[0].id" \
  --output tsv)

NIC_NAME=$(basename "${NIC_ID}")

az network nic update \
  --name "${NIC_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --ip-forwarding true \
  --output none

log_info "  ✓ IP forwarding enabled on ${NIC_NAME}"
log_info ""

# Step 3: Enable IP forwarding in the VM OS
log_info "Step 3: Enabling IP forwarding in VM OS..."
az vm run-command invoke \
  --name "${NVA_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --command-id RunShellScript \
  --scripts "sysctl -w net.ipv4.ip_forward=1 && echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf" \
  --output none

log_info "  ✓ IP forwarding enabled in OS"
log_info ""

# Step 4: Create route table
log_info "Step 4: Creating route table..."
if ! az network route-table show --name "${ROUTE_TABLE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME}" \
  "${SCRIPT_DIR}/resource-route-table.sh"
  log_info "  ✓ Route table created: ${ROUTE_TABLE_NAME}"
else
  log_info "  ✓ Route table exists: ${ROUTE_TABLE_NAME}"
fi
log_info ""

# Step 5: Add default route pointing to NVA
log_info "Step 5: Adding default route (0.0.0.0/0 -> ${NVA_IP})..."
if ! az network route-table route show \
  --name "default-via-nva" \
  --route-table-name "${ROUTE_TABLE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME}" \
  ROUTE_NAME="default-via-nva" \
  ADDRESS_PREFIX="0.0.0.0/0" \
  NEXT_HOP_TYPE="VirtualAppliance" \
  NEXT_HOP_IP="${NVA_IP}" \
  "${SCRIPT_DIR}/resource-route.sh"
  log_info "  ✓ Route added: 0.0.0.0/0 -> ${NVA_IP}"
else
  log_info "  ✓ Route exists: 0.0.0.0/0 -> ${NVA_IP}"
fi
log_info ""

# Step 6: Associate route table with subnet4
log_info "Step 6: Associating route table with snet-subnet4..."
az network vnet subnet update \
  --name "snet-subnet4" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --route-table "${ROUTE_TABLE_NAME}" \
  --output none

log_info "  ✓ Route table associated with snet-subnet4"
log_info ""

log_info "========================================="
log_info "NVA Routing Configuration Complete!"
log_info "========================================="
log_info ""
log_info "Configuration Summary:"
log_info "  • NVA VM: ${NVA_VM} (${NVA_IP})"
log_info "  • Route Table: ${ROUTE_TABLE_NAME}"
log_info "  • Route: 0.0.0.0/0 -> ${NVA_IP} (VirtualAppliance)"
log_info "  • Applied to: snet-subnet4 (10.0.40.0/24)"
log_info ""
log_info "Traffic flow:"
log_info "  subnet4 VM -> UDR (0.0.0.0/0) -> ${NVA_IP} (NVA) -> Internet"
log_info ""
log_info "Next steps:"
log_info "  1. Update nftables on NVA to allow NAT (run 08-nftables.sh)"
log_info "  2. Run 15-nva-tests.sh to verify routing works"
log_info ""
log_warn "Note: NVA must have nftables NAT configured for internet access to work"
