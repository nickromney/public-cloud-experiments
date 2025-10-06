#!/usr/bin/env bash
#
# Interactive NSG demonstration
# Shows how NSG rules control traffic between subnets
# Tests: ICMP, HTTP, TCP connectivity

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly NSG_NAME="${NSG_NAME:-nsg-simple}"
readonly CONTAINER1="${CONTAINER1:-aci-custom-subnet1}"
readonly CONTAINER2="${CONTAINER2:-aci-custom-subnet2}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_demo() { echo -e "${BLUE}[DEMO]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_demo "========================================="
log_demo "Azure NSG (Network Security Group) Demo"
log_demo "========================================="
log_demo ""

# Get container IPs
log_info "Getting container IP addresses..."
CONTAINER1_IP=$(az container show \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv 2>/dev/null || echo "")

CONTAINER2_IP=$(az container show \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "${CONTAINER1_IP}" ]] || [[ -z "${CONTAINER2_IP}" ]]; then
  log_error "Containers not found. Deploy with 09-custom-containers.sh first"
  exit 1
fi

log_info "  ${CONTAINER1}: ${CONTAINER1_IP}"
log_info "  ${CONTAINER2}: ${CONTAINER2_IP}"
log_info ""

# Show current NSG rules
log_demo "Current NSG Rules:"
az network nsg rule list \
  --nsg-name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].{Name:name, Priority:priority, Direction:direction, Access:access, Protocol:protocol, SourcePort:sourcePortRange, DestPort:destinationPortRange, Source:sourceAddressPrefix, Dest:destinationAddressPrefix}" \
  --output table

echo ""
read -r -p "Press Enter to continue..."
echo ""

# Test 1: Baseline connectivity
log_demo "========================================="
log_demo "Test 1: Baseline HTTP Connectivity"
log_demo "========================================="
log_info "Testing ${CONTAINER2} -> ${CONTAINER1} HTTP (should work)"
if timeout 10 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "curl -s -o /dev/null -w %{http_code} --max-time 3 http://${CONTAINER1_IP}" 2>/dev/null | grep -qE "^(200|301|302)"; then
  log_info "  ✓ HTTP works (baseline)"
else
  log_error "  ✗ HTTP failed (unexpected)"
fi
echo ""
read -r -p "Press Enter to block HTTP traffic..."
echo ""

# Test 2: Block HTTP
log_demo "========================================="
log_demo "Test 2: Block HTTP Traffic (Port 80)"
log_demo "========================================="
log_info "Creating NSG rule to deny HTTP..."
RULE_NAME=DenyHTTP \
PRIORITY=90 \
DIRECTION=Inbound \
ACCESS=Deny \
PROTOCOL=Tcp \
SOURCE_PREFIX="*" \
DEST_PREFIX="*" \
DEST_PORT=80 \
ACTION=create \
"${SCRIPT_DIR}/resource-nsg-rule.sh"

log_info "Waiting 10 seconds for rule to propagate..."
sleep 10

log_info "Testing ${CONTAINER2} -> ${CONTAINER1} HTTP (should fail)"
if timeout 10 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "curl -s -o /dev/null -w %{http_code} --max-time 3 http://${CONTAINER1_IP}" 2>/dev/null | grep -qE "^(200|301|302)"; then
  log_error "  ✗ HTTP works (unexpected - should be blocked)"
else
  log_info "  ✓ HTTP blocked by NSG rule"
fi
echo ""
read -r -p "Press Enter to restore HTTP traffic..."
echo ""

# Test 3: Restore HTTP
log_demo "========================================="
log_demo "Test 3: Restore HTTP Traffic"
log_demo "========================================="
log_info "Deleting DenyHTTP rule..."
RULE_NAME=DenyHTTP \
ACTION=delete \
"${SCRIPT_DIR}/resource-nsg-rule.sh"

log_info "Waiting 10 seconds for rule to propagate..."
sleep 10

log_info "Testing ${CONTAINER2} -> ${CONTAINER1} HTTP (should work again)"
if timeout 10 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "curl -s -o /dev/null -w %{http_code} --max-time 3 http://${CONTAINER1_IP}" 2>/dev/null | grep -qE "^(200|301|302)"; then
  log_info "  ✓ HTTP works again (rule removed)"
else
  log_error "  ✗ HTTP still blocked (unexpected)"
fi

log_demo ""
log_demo "========================================="
log_demo "Demo Complete!"
log_demo "========================================="
log_info ""
log_info "Key Takeaways:"
log_info "  • NSG rules control traffic at subnet/NIC level"
log_info "  • Deny rules take precedence over allow rules"
log_info "  • Rules are stateful (return traffic automatically allowed)"
log_info "  • Changes take ~10 seconds to propagate"
