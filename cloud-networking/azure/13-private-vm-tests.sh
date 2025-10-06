#!/usr/bin/env bash
#
# Test private VM connectivity
# Verify:
#   ✓ Can reach other subnets
#   ✗ Cannot reach internet (no default outbound access)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VM_NAME="${VM_NAME:-vm-test4}"
readonly CONTAINER1="${CONTAINER1:-aci-custom-subnet1}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

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

log_info "Testing private VM connectivity..."
log_info ""

# Get VM private IP
VM_IP=$(az vm show \
  --name "${VM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --show-details \
  --query "privateIps" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "${VM_IP}" ]]; then
  log_error "VM ${VM_NAME} not found. Deploy with 12-private-vm.sh first"
  exit 1
fi

log_info "VM Details:"
log_info "  Name: ${VM_NAME}"
log_info "  Private IP: ${VM_IP}"
log_info "  Subnet: snet-subnet4 (10.0.40.0/24, private)"
log_info ""

# Get container IP for inter-subnet test
CONTAINER1_IP=$(az container show \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv 2>/dev/null || echo "")

if [[ -n "${CONTAINER1_IP}" ]]; then
  log_info "Target container: ${CONTAINER1} at ${CONTAINER1_IP}"
else
  log_warn "Container ${CONTAINER1} not found, skipping inter-subnet test"
fi

log_info ""
log_info "========================================="
log_info "Test 1: Internet Connectivity (should FAIL)"
log_info "========================================="
log_info "Testing: curl http://google.com from ${VM_NAME}..."

INTERNET_RESULT=$(az vm run-command invoke \
  --name "${VM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --command-id RunShellScript \
  --scripts "curl -I -s -o /dev/null -w '%{http_code}' --max-time 5 http://google.com || echo 'timeout'" \
  --query "value[0].message" \
  --output tsv 2>/dev/null || echo "error")

if echo "${INTERNET_RESULT}" | grep -qE "(timeout|000|error)"; then
  log_info "  ✓ Internet blocked (expected - private subnet)"
else
  log_error "  ✗ Internet accessible (unexpected - got: ${INTERNET_RESULT})"
fi

log_info ""
log_info "========================================="
log_info "Test 2: Inter-Subnet Connectivity (should PASS)"
log_info "========================================="

if [[ -n "${CONTAINER1_IP}" ]]; then
  log_info "Testing: curl http://${CONTAINER1_IP} from ${VM_NAME}..."

  SUBNET_RESULT=$(az vm run-command invoke \
    --name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://${CONTAINER1_IP}" \
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
log_info "========================================="
log_info "Test Summary"
log_info "========================================="
log_info ""
log_info "Key Findings:"
log_info "  • Private subnet (defaultOutboundAccess: false) blocks internet"
log_info "  • Inter-subnet traffic allowed by NSG rules"
log_info "  • To enable internet: add NAT Gateway or route through NVA"
log_info ""
log_info "Next steps:"
log_info "  • Run 14-nva-routing.sh to route traffic through NVA"
log_info "  • This will enable internet via subnet3 VM acting as router"
