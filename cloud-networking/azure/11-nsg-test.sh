#!/usr/bin/env bash
#
# Automated NSG rule testing
# Verifies NSG rules are working as expected

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly NSG_NAME="${NSG_NAME:-nsg-simple}"
readonly CONTAINER1="${CONTAINER1:-aci-custom-subnet1}"
readonly CONTAINER2="${CONTAINER2:-aci-custom-subnet2}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
# readonly YELLOW='\033[1;33m'  # Unused currently
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
# log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }  # Unused currently

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
  local test_name=$1
  local expected=$2
  local command=$3

  ((TESTS_RUN++))
  log_info "Test ${TESTS_RUN}: ${test_name}"

  if eval "${command}"; then
    local result="PASS"
  else
    local result="FAIL"
  fi

  if [[ "${result}" == "${expected}" ]]; then
    log_info "  ✓ ${expected} (as expected)"
    ((TESTS_PASSED++))
  else
    log_error "  ✗ ${result} (expected ${expected})"
  fi
}

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_info "Running NSG rule tests..."
log_info ""

# Get container IPs
CONTAINER1_IP=$(az container show --name "${CONTAINER1}" --resource-group "${RESOURCE_GROUP}" --query "ipAddress.ip" --output tsv 2>/dev/null || echo "")
CONTAINER2_IP=$(az container show --name "${CONTAINER2}" --resource-group "${RESOURCE_GROUP}" --query "ipAddress.ip" --output tsv 2>/dev/null || echo "")

if [[ -z "${CONTAINER1_IP}" ]] || [[ -z "${CONTAINER2_IP}" ]]; then
  log_error "Containers not found. Deploy with 09-custom-containers.sh first"
  exit 1
fi

log_info "Container IPs: ${CONTAINER1}: ${CONTAINER1_IP}, ${CONTAINER2}: ${CONTAINER2_IP}"
log_info ""

# Test HTTP connectivity (should work with default NSG)
run_test "HTTP connectivity (baseline)" "PASS" \
  "timeout 10 az container exec --name ${CONTAINER2} --resource-group ${RESOURCE_GROUP} --exec-command 'curl -s -o /dev/null -w %{http_code} --max-time 3 http://${CONTAINER1_IP}' 2>/dev/null | grep -qE '^(200|301|302)'"

# Test netcat connectivity
run_test "Netcat port 80 (baseline)" "PASS" \
  "timeout 10 az container exec --name ${CONTAINER2} --resource-group ${RESOURCE_GROUP} --exec-command 'nc -nvw 3 ${CONTAINER1_IP} 80' 2>&1 | grep -qE '(succeeded|open)'"

log_info ""
log_info "========================================="
log_info "Test Summary:"
log_info "  Tests Run: ${TESTS_RUN}"
log_info "  Tests Passed: ${TESTS_PASSED}"
log_info "  Tests Failed: $((TESTS_RUN - TESTS_PASSED))"
log_info "========================================="

if [[ ${TESTS_PASSED} -eq ${TESTS_RUN} ]]; then
  log_info "✓ All tests passed!"
  exit 0
else
  log_error "✗ Some tests failed"
  exit 1
fi
