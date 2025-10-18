#!/usr/bin/env bash
#
# Detect if Static Web App uses managed or BYO (Bring Your Own) functions
#
# Azure Static Web Apps support three function deployment models:
# 1. Managed Functions - SWA automatically provisions and manages Azure Functions
# 2. BYO Linked - Static Web App linked to an existing Function App
# 3. BYO Unlinked - Separate Function App exists but not linked to SWA
#
# Usage:
#   # Check specific Static Web App
#   ./lib/detect-function-type.sh stapp-subnet-calc rg-subnet-calc
#
#   # Use in a script
#   FUNCTION_TYPE=$(./lib/detect-function-type.sh stapp-subnet-calc rg-subnet-calc)
#   if [[ "${FUNCTION_TYPE}" == "byo-linked" ]]; then
#     echo "Using linked Function App"
#   fi
#
# Parameters:
#   $1 - Static Web App name
#   $2 - Resource group name
#
# Returns (stdout):
#   managed       - SWA uses managed functions (no separate Function App)
#   byo-linked    - SWA is linked to a Function App via backends
#   byo-unlinked  - Function App exists but not linked to SWA
#   none          - No functions detected (static content only)
#
# Exit Codes:
#   0 - Success (function type detected)
#   1 - Error (resource not found or Azure CLI error)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Read permissions on Static Web App and Function Apps

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
# shellcheck disable=SC2317  # Function called indirectly
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Usage
usage() {
  cat <<EOF >&2
Usage: $0 STATIC_WEB_APP_NAME RESOURCE_GROUP

Detect if Static Web App uses managed or BYO functions.

Arguments:
  STATIC_WEB_APP_NAME - Name of the Static Web App
  RESOURCE_GROUP      - Resource group containing the SWA

Returns:
  managed      - SWA uses managed functions (no separate Function App)
  byo-linked   - SWA is linked to a Function App
  byo-unlinked - Function App exists but not linked to SWA
  none         - No functions detected (static content only)

Examples:
  # Check function type
  ./lib/detect-function-type.sh stapp-subnet-calc rg-subnet-calc

  # Use in script
  TYPE=\$(./lib/detect-function-type.sh stapp-subnet-calc rg-subnet-calc)
  if [[ "\${TYPE}" == "byo-linked" ]]; then
    echo "Using BYO Function App"
  fi

Exit Codes:
  0 - Success
  1 - Error
EOF
}

# Parse arguments
if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

readonly STATIC_WEB_APP_NAME="$1"
readonly RESOURCE_GROUP="$2"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Verify Static Web App exists
log_info "Checking Static Web App: ${STATIC_WEB_APP_NAME}"

if ! az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi

# Check for linked backends
log_info "Checking for linked backends..."

LINKED_BACKENDS=$(az staticwebapp backends list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${LINKED_BACKENDS}" -gt 0 ]]; then
  # BYO linked - backend is explicitly linked
  log_info "Found ${LINKED_BACKENDS} linked backend(s)"

  # Get backend details
  BACKEND_INFO=$(az staticwebapp backends list \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].[backendResourceId,region]" -o tsv 2>/dev/null || echo "")

  if [[ -n "${BACKEND_INFO}" ]]; then
    BACKEND_ID=$(echo "${BACKEND_INFO}" | awk '{print $1}')
    BACKEND_REGION=$(echo "${BACKEND_INFO}" | awk '{print $2}')

    log_info "Linked backend:"
    log_info "  Resource ID: ${BACKEND_ID}"
    log_info "  Region: ${BACKEND_REGION}"
  fi

  echo "byo-linked"
  exit 0
fi

# No linked backends - check if there are Function Apps in the resource group
log_info "No linked backends found. Checking for unlinked Function Apps..."

FUNCTION_APPS=$(az functionapp list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${FUNCTION_APPS}" -gt 0 ]]; then
  # Function Apps exist but not linked to SWA
  log_info "Found ${FUNCTION_APPS} Function App(s) in resource group (unlinked)"

  # List Function Apps
  FUNC_LIST=$(az functionapp list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].[name,defaultHostName]" -o tsv 2>/dev/null || echo "")

  if [[ -n "${FUNC_LIST}" ]]; then
    log_info "Unlinked Function Apps:"
    echo "${FUNC_LIST}" | while IFS=$'\t' read -r name hostname; do
      log_info "  - ${name} (https://${hostname})"
    done
  fi

  echo "byo-unlinked"
  exit 0
fi

# No backends and no Function Apps - check for managed functions
log_info "No Function Apps found. Checking for managed functions..."

# Check if SWA has API configuration
# Note: Azure CLI doesn't directly expose managed function status
# We can infer from the SWA configuration if it has functions enabled

SWA_CONFIG=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{sku:sku.name,provider:provider}" -o json 2>/dev/null || echo "{}")

SKU=$(echo "${SWA_CONFIG}" | jq -r '.sku // "Unknown"')
PROVIDER=$(echo "${SWA_CONFIG}" | jq -r '.provider // "Unknown"')

log_info "Static Web App configuration:"
log_info "  SKU: ${SKU}"
log_info "  Provider: ${PROVIDER}"

# Check if SWA has functions directory (requires deployment to check)
# For now, we'll infer based on the absence of BYO functions

# If Standard or higher SKU and no BYO, likely has managed functions
if [[ "${SKU}" =~ (Standard|Premium) ]]; then
  log_info "Standard/Premium SKU detected - may have managed functions"
  echo "managed"
  exit 0
fi

# Free tier or no function configuration detected
log_info "No functions detected (static content only)"
echo "none"
exit 0
