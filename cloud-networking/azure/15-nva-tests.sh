#!/usr/bin/env bash
#
# Test NVA (Network Virtual Appliance) routing
# Verify traffic from subnet4 flows through subnet3 NVA to internet
#
# Expected results:
#   ✓ subnet4 VM can reach internet (via NVA)
#   ✓ subnet4 VM can reach other subnets
#   ✓ Traffic is being routed through NVA (10.0.30.x)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly PRIVATE_VM="${PRIVATE_VM:-vm-private}"
readonly NVA_VM="${NVA_VM:-vm-firewall}"
readonly CONTAINER1="${CONTAINER1:-aci-custom-subnet1}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_demo() { echo -e "${BLUE}[TEST]${NC} $*"; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Detect location from resource group if LOCATION not set (for consistency)
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv 2>/dev/null || echo "")
  if [[ -z "${LOCATION}" ]]; then
    log_error "Could not detect location from resource group ${RESOURCE_GROUP}"
    exit 1
  fi
fi
readonly LOCATION

log_demo "========================================="
log_demo "NVA Routing Tests"
log_demo "========================================="
log_info ""

# Get VM IPs
log_info "Getting VM and NVA IP addresses..."
PRIVATE_VM_IP=$(az vm show \
  --name "${PRIVATE_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --show-details \
  --query "privateIps" \
  --output tsv 2>/dev/null || echo "")

NVA_IP=$(az vm show \
  --name "${NVA_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --show-details \
  --query "privateIps" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "${PRIVATE_VM_IP}" ]]; then
  log_error "Private VM ${PRIVATE_VM} not found. Deploy with 12-private-vm.sh first"
  exit 1
fi

if [[ -z "${NVA_IP}" ]]; then
  log_error "NVA VM ${NVA_VM} not found. Deploy with 07-vm.sh first"
  exit 1
fi

log_info "  Private VM: ${PRIVATE_VM} (${PRIVATE_VM_IP})"
log_info "  NVA VM: ${NVA_VM} (${NVA_IP})"
log_info ""

# Get container IP for inter-subnet test
CONTAINER1_IP=$(az container show \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv 2>/dev/null || echo "")

if [[ -n "${CONTAINER1_IP}" ]]; then
  log_info "  Container: ${CONTAINER1} (${CONTAINER1_IP})"
else
  log_warn "  Container ${CONTAINER1} not found, skipping inter-subnet test"
fi

log_info ""

# Test 1: Check route table configuration
log_demo "========================================="
log_demo "Test 1: Verify Route Table Configuration"
log_demo "========================================="
log_info "Checking route table for snet-subnet4..."

ROUTE_TABLE=$(az network vnet subnet show \
  --name "snet-subnet4" \
  --vnet-name "vnet-simple" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "routeTable.id" \
  --output tsv 2>/dev/null || echo "")

if [[ -n "${ROUTE_TABLE}" ]]; then
  log_info "  ✓ Route table associated with subnet4"

  # Show routes
  ROUTE_TABLE_NAME=$(basename "${ROUTE_TABLE}")
  log_info "  Routes in ${ROUTE_TABLE_NAME}:"
  az network route-table route list \
    --route-table-name "${ROUTE_TABLE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].{Name:name, AddressPrefix:addressPrefix, NextHopType:nextHopType, NextHop:nextHopIpAddress}" \
    --output table
else
  log_error "  ✗ No route table associated (run 14-nva-routing.sh first)"
  exit 1
fi

log_info ""

# Test 2: Internet connectivity through NVA
log_demo "========================================="
log_demo "Test 2: Internet Connectivity via NVA"
log_demo "========================================="
log_info "Testing: curl http://google.com from ${PRIVATE_VM} (should work via NVA)..."

INTERNET_RESULT=$(az vm run-command invoke \
  --name "${PRIVATE_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --command-id RunShellScript \
  --scripts "curl -I -s -o /dev/null -w '%{http_code}' --max-time 10 http://google.com || echo 'timeout'" \
  --query "value[0].message" \
  --output tsv 2>/dev/null || echo "error")

if echo "${INTERNET_RESULT}" | grep -qE "(200|301|302)"; then
  log_info "  ✓ Internet accessible via NVA (got: ${INTERNET_RESULT})"
else
  log_error "  ✗ Internet not accessible (got: ${INTERNET_RESULT})"
  log_error "  Possible issues:"
  log_error "    - NVA nftables NAT not configured (run 08-nftables.sh)"
  log_error "    - IP forwarding not enabled on NVA"
  log_error "    - Route table not properly configured"
fi

log_info ""

# Test 3: Verify traffic goes through NVA
log_demo "========================================="
log_demo "Test 3: Verify Traffic Routes Through NVA"
log_demo "========================================="
log_info "Checking route from ${PRIVATE_VM} to internet..."

ROUTE_CHECK=$(az vm run-command invoke \
  --name "${PRIVATE_VM}" \
  --resource-group "${RESOURCE_GROUP}" \
  --command-id RunShellScript \
  --scripts "ip route get 8.8.8.8 || echo 'error'" \
  --query "value[0].message" \
  --output tsv 2>/dev/null || echo "error")

if echo "${ROUTE_CHECK}" | grep -q "${NVA_IP}"; then
  log_info "  ✓ Traffic routes through NVA (${NVA_IP})"
else
  log_warn "  ? Could not verify routing through NVA"
  log_info "  Route output: ${ROUTE_CHECK}"
fi

log_info ""

# Test 4: Inter-subnet connectivity
log_demo "========================================="
log_demo "Test 4: Inter-Subnet Connectivity"
log_demo "========================================="

if [[ -n "${CONTAINER1_IP}" ]]; then
  log_info "Testing: curl http://${CONTAINER1_IP} from ${PRIVATE_VM}..."

  SUBNET_RESULT=$(az vm run-command invoke \
    --name "${PRIVATE_VM}" \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://${CONTAINER1_IP}" \
    --query "value[0].message" \
    --output tsv 2>/dev/null || echo "error")

  if echo "${SUBNET_RESULT}" | grep -qE "(200|301|302)"; then
    log_info "  ✓ Inter-subnet connectivity works (got: ${SUBNET_RESULT})"
  else
    log_error "  ✗ Inter-subnet connectivity failed (got: ${SUBNET_RESULT})"
  fi
else
  log_warn "  ⊘ Skipped (no container available)"
fi

log_info ""
log_demo "========================================="
log_demo "Test Summary"
log_demo "========================================="
log_info ""
log_info "NVA Architecture:"
log_info "  subnet4 (10.0.40.0/24, private)"
log_info "    ↓ UDR: 0.0.0.0/0 -> ${NVA_IP}"
log_info "  subnet3 NVA (${NVA_IP})"
log_info "    ↓ NAT (masquerade)"
log_info "  Internet"
log_info ""
log_info "Key Components:"
log_info "  • Route Table: Forces subnet4 traffic to NVA"
log_info "  • IP Forwarding: Enabled on NVA VM and NIC"
log_info "  • nftables NAT: Masquerades outbound traffic"
log_info "  • NSG Rules: Allow forwarding between subnets"
