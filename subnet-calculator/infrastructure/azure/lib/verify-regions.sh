#!/usr/bin/env bash
#
# Verify data sovereignty compliance by checking resource regions
#
# This script verifies that Azure resources are deployed in expected regions,
# helping ensure compliance with data sovereignty requirements (GDPR, UK data laws, etc.)
#
# Usage:
#   # Check if Function App is in UK region
#   ./lib/verify-regions.sh func-subnet-calc-123456 rg-subnet-calc UK
#
#   # Check if resources are in EU regions
#   ./lib/verify-regions.sh func-subnet-calc-123456 rg-subnet-calc EU
#
#   # Check against specific region
#   ./lib/verify-regions.sh func-subnet-calc-123456 rg-subnet-calc uksouth
#
# Parameters:
#   $1 - Resource name (Function App, Storage Account, etc.)
#   $2 - Resource group name
#   $3 - Expected region or sovereignty zone (UK, EU, US, uksouth, westeurope, etc.)
#
# Sovereignty Zones:
#   UK  - United Kingdom regions (uksouth, ukwest)
#   EU  - European Union regions (westeurope, northeurope, francecentral, etc.)
#   US  - United States regions (eastus, westus, centralus, etc.)
#   Or specify exact region name (e.g., uksouth)
#
# Exit Codes:
#   0 - Compliance verified (region matches)
#   1 - Compliance failure (region mismatch or error)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Read permissions on the resource

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
# shellcheck disable=SC2317  # Function called indirectly
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; }

# Usage
usage() {
  cat <<EOF
Usage: $0 RESOURCE_NAME RESOURCE_GROUP EXPECTED_REGION_OR_ZONE

Verify data sovereignty compliance by checking resource regions.

Arguments:
  RESOURCE_NAME   - Name of the Azure resource to check
  RESOURCE_GROUP  - Resource group containing the resource
  EXPECTED_REGION - Expected region or sovereignty zone

Sovereignty Zones:
  UK  - United Kingdom regions (uksouth, ukwest)
  EU  - European Union regions (westeurope, northeurope, francecentral, etc.)
  US  - United States regions (eastus, westus, centralus, etc.)
  Or specify exact region name (e.g., uksouth)

Examples:
  # Check Function App is in UK
  $0 func-subnet-calc-123456 rg-subnet-calc UK

  # Check Storage Account is in EU
  $0 stsubnetcalc123456 rg-subnet-calc EU

  # Check resource is in specific region
  $0 func-subnet-calc-123456 rg-subnet-calc uksouth

Exit Codes:
  0 - Compliance verified (region matches)
  1 - Compliance failure (region mismatch or error)
EOF
}

# Parse arguments
if [[ $# -ne 3 ]]; then
  usage
  exit 1
fi

readonly RESOURCE_NAME="$1"
readonly RESOURCE_GROUP="$2"
readonly EXPECTED_REGION="$3"

# Region mappings for sovereignty zones
declare -A REGION_ZONES=(
  # UK regions
  ["uksouth"]="UK"
  ["ukwest"]="UK"

  # EU regions
  ["westeurope"]="EU"
  ["northeurope"]="EU"
  ["francecentral"]="EU"
  ["francesouth"]="EU"
  ["germanywestcentral"]="EU"
  ["norwayeast"]="EU"
  ["norwaywest"]="EU"
  ["swedencentral"]="EU"
  ["switzerlandnorth"]="EU"
  ["switzerlandwest"]="EU"

  # US regions
  ["eastus"]="US"
  ["eastus2"]="US"
  ["westus"]="US"
  ["westus2"]="US"
  ["westus3"]="US"
  ["centralus"]="US"
  ["northcentralus"]="US"
  ["southcentralus"]="US"
  ["westcentralus"]="US"
)

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Try to get resource location (works for most Azure resources)
log_info "Checking location for resource: ${RESOURCE_NAME}"

# Try as Function App first
ACTUAL_REGION=$(az functionapp show \
  --name "${RESOURCE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query location -o tsv 2>/dev/null || echo "")

# If not a Function App, try as generic resource
if [[ -z "${ACTUAL_REGION}" ]]; then
  ACTUAL_REGION=$(az resource show \
    --name "${RESOURCE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query location -o tsv 2>/dev/null || echo "")
fi

# If still not found, resource doesn't exist
if [[ -z "${ACTUAL_REGION}" ]]; then
  log_error "Resource ${RESOURCE_NAME} not found in resource group ${RESOURCE_GROUP}"
  log_error "Verify resource name and resource group are correct"
  exit 1
fi

log_info "Actual region: ${ACTUAL_REGION}"
log_info "Expected region/zone: ${EXPECTED_REGION}"

# Normalize region names (remove spaces, lowercase)
ACTUAL_REGION_NORMALIZED=$(echo "${ACTUAL_REGION}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
EXPECTED_REGION_NORMALIZED=$(echo "${EXPECTED_REGION}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# Check if expected region is a sovereignty zone (UK, EU, US)
if [[ "${EXPECTED_REGION_NORMALIZED}" =~ ^(uk|eu|us)$ ]]; then
  # Zone-based check
  ACTUAL_ZONE="${REGION_ZONES[${ACTUAL_REGION_NORMALIZED}]:-Unknown}"

  if [[ "${ACTUAL_ZONE}" == "${EXPECTED_REGION_NORMALIZED^^}" ]]; then
    log_success "Data sovereignty compliance verified"
    log_info "Resource: ${RESOURCE_NAME}"
    log_info "Location: ${ACTUAL_REGION} (${ACTUAL_ZONE} zone)"
    log_info "Expected: ${EXPECTED_REGION} zone"
    exit 0
  else
    log_fail "Data sovereignty compliance failure"
    log_error "Resource: ${RESOURCE_NAME}"
    log_error "Location: ${ACTUAL_REGION} (${ACTUAL_ZONE} zone)"
    log_error "Expected: ${EXPECTED_REGION} zone"
    log_error ""
    log_error "This resource may not comply with ${EXPECTED_REGION} data sovereignty requirements"
    exit 1
  fi
else
  # Exact region check
  if [[ "${ACTUAL_REGION_NORMALIZED}" == "${EXPECTED_REGION_NORMALIZED}" ]]; then
    log_success "Region compliance verified"
    log_info "Resource: ${RESOURCE_NAME}"
    log_info "Location: ${ACTUAL_REGION}"
    log_info "Expected: ${EXPECTED_REGION}"
    exit 0
  else
    log_fail "Region compliance failure"
    log_error "Resource: ${RESOURCE_NAME}"
    log_error "Location: ${ACTUAL_REGION}"
    log_error "Expected: ${EXPECTED_REGION}"
    log_error ""
    log_error "Resource is not in the expected region"
    exit 1
  fi
fi
