#!/usr/bin/env bash
#
# Test network connectivity between container instances
# - Check/install network tools (curl, netcat) in both containers
# - Test internet connectivity from both subnets (ACI delegation requires outbound access)
# - Test inter-subnet connectivity (should work)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly CONTAINER1="${CONTAINER1:-aci-subnet1}"
readonly CONTAINER2="${CONTAINER2:-aci-subnet2}"

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

log_info "Testing network connectivity between containers"
log_info ""

# Get container IPs
log_info "Getting container IP addresses..."
CONTAINER1_IP=$(az container show \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv)

CONTAINER2_IP=$(az container show \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv)

if [[ -z "${CONTAINER1_IP}" ]] || [[ -z "${CONTAINER2_IP}" ]]; then
  log_error "Failed to get container IPs. Are containers deployed?"
  exit 1
fi

log_info "Container IPs:"
log_info "  ${CONTAINER1}: ${CONTAINER1_IP} (subnet1)"
log_info "  ${CONTAINER2}: ${CONTAINER2_IP} (subnet2)"
log_info ""

# Check available tools in containers
log_info "Checking available tools in containers..."

# Helper function to check tools
check_tools() {
  local container_name=$1
  log_info "  ${container_name}:"

  # Check for nc (netcat)
  local has_nc
  has_nc=$(az container exec --name "${container_name}" --resource-group "${RESOURCE_GROUP}" --exec-command "which nc" 2>/dev/null || echo "")

  # Check for wget (pre-installed in nginx alpine)
  local has_wget
  has_wget=$(az container exec --name "${container_name}" --resource-group "${RESOURCE_GROUP}" --exec-command "which wget" 2>/dev/null || echo "")

  if [[ -n "${has_nc}" ]]; then
    log_info "    ✓ nc available"
  else
    log_warn "    ✗ nc not available"
  fi

  if [[ -n "${has_wget}" ]]; then
    log_info "    ✓ wget available"
  else
    log_warn "    ✗ wget not available"
  fi
}

# Check tools in both containers
check_tools "${CONTAINER1}"
check_tools "${CONTAINER2}"

log_info ""

# Test 1: Internet from subnet1 (should work)
log_info "Test 1: Internet connectivity from ${CONTAINER1} (should work)..."
if timeout 15 az container exec \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command 'wget -s -T 5 -q http://google.com' 2>&1; then
  log_info "  ✓ ${CONTAINER1} can reach internet"
else
  log_error "  ✗ ${CONTAINER1} cannot reach internet"
fi

log_info ""

# Test 2: Internet from subnet2 (note: ACI delegation prevents --default-outbound false)
log_info "Test 2: Internet connectivity from ${CONTAINER2}..."
if timeout 15 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command 'wget -s -T 5 -q http://google.com' 2>&1; then
  log_info "  ✓ ${CONTAINER2} can reach internet - Note: ACI delegation requires outbound access"
else
  log_warn "  ✗ ${CONTAINER2} cannot reach internet"
fi

log_info ""

# Test 3: Inter-subnet connectivity with netcat (subnet2 -> subnet1)
log_info "Test 3: Inter-subnet connectivity with netcat (${CONTAINER2} -> ${CONTAINER1})..."
if timeout 10 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "nc -nvzw 3 ${CONTAINER1_IP} 80" 2>&1 | grep -qE "(succeeded|open)"; then
  log_info "  ✓ ${CONTAINER2} can reach ${CONTAINER1} (netcat)"
else
  log_error "  ✗ ${CONTAINER2} cannot reach ${CONTAINER1} (unexpected)"
fi

log_info ""

# Test 4: Inter-subnet connectivity with HTTP (subnet2 -> subnet1)
log_info "Test 4: Inter-subnet connectivity with HTTP (${CONTAINER2} -> ${CONTAINER1})..."
if timeout 10 az container exec \
  --name "${CONTAINER2}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "wget -s -T 3 -q http://${CONTAINER1_IP}" 2>&1; then
  log_info "  ✓ ${CONTAINER2} can HTTP to ${CONTAINER1}"
else
  log_warn "  ✗ ${CONTAINER2} cannot HTTP to ${CONTAINER1}"
fi

log_info ""

# Test 5: Inter-subnet connectivity with netcat (subnet1 -> subnet2)
log_info "Test 5: Inter-subnet connectivity with netcat (${CONTAINER1} -> ${CONTAINER2})..."
if timeout 10 az container exec \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "nc -nvzw 3 ${CONTAINER2_IP} 80" 2>&1 | grep -qE "(succeeded|open)"; then
  log_info "  ✓ ${CONTAINER1} can reach ${CONTAINER2} (netcat)"
else
  log_error "  ✗ ${CONTAINER1} cannot reach ${CONTAINER2} (unexpected)"
fi

log_info ""

# Test 6: Inter-subnet connectivity with HTTP (subnet1 -> subnet2)
log_info "Test 6: Inter-subnet connectivity with HTTP (${CONTAINER1} -> ${CONTAINER2})..."
if timeout 10 az container exec \
  --name "${CONTAINER1}" \
  --resource-group "${RESOURCE_GROUP}" \
  --exec-command "wget -s -T 3 -q http://${CONTAINER2_IP}" 2>&1; then
  log_info "  ✓ ${CONTAINER1} can HTTP to ${CONTAINER2}"
else
  log_warn "  ✗ ${CONTAINER1} cannot HTTP to ${CONTAINER2}"
fi

log_info ""
log_info "Network connectivity tests complete!"
