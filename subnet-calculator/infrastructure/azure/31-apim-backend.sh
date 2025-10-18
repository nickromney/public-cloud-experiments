#!/usr/bin/env bash
#
# Configure Azure API Management backend for Function App
# - Imports API from Function App OpenAPI spec
# - Creates backend pointing to Function App
# - Sets up API paths and operations
# - Verifies health endpoint connectivity

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory and source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/selection-utils.sh
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Auto-detect or prompt for APIM_NAME
if [[ -z "${APIM_NAME:-}" ]]; then
  log_info "APIM_NAME not set. Looking for APIM instances in ${RESOURCE_GROUP}..."
  APIM_COUNT=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${APIM_COUNT}" -eq 0 ]]; then
    log_error "No APIM instances found in ${RESOURCE_GROUP}"
    log_error "Run ./30-apim-instance.sh first"
    exit 1
  elif [[ "${APIM_COUNT}" -eq 1 ]]; then
    APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected APIM instance: ${APIM_NAME}"
  else
    log_warn "Multiple APIM instances found:"
    APIM_NAME=$(select_apim_instance "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${APIM_NAME}"
  fi
fi

# Auto-detect or prompt for FUNCTION_APP_NAME
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  log_info "FUNCTION_APP_NAME not set. Looking for Function Apps in ${RESOURCE_GROUP}..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in ${RESOURCE_GROUP}"
    log_error "Run ./10-function-app.sh first"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Function App: ${FUNCTION_APP_NAME}"
  else
    log_warn "Multiple Function Apps found:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

# Configuration
readonly API_PATH="${API_PATH:-subnet-calc}"  # URL path: /subnet-calc/api/v1/*
readonly API_DISPLAY_NAME="${API_DISPLAY_NAME:-Subnet Calculator API}"

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  APIM Name: ${APIM_NAME}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  API Path: /${API_PATH}"

# Verify APIM exists
if ! az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "APIM instance ${APIM_NAME} not found"
  log_error "Run ./30-apim-instance.sh first"
  exit 1
fi

# Verify Function App exists
if ! az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found"
  log_error "Run ./10-function-app.sh first"
  exit 1
fi

# Get Function App details
FUNCTION_URL=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.defaultHostName" -o tsv)

log_info "Function App URL: https://${FUNCTION_URL}"

# Download OpenAPI spec from Function App
log_info "Downloading OpenAPI spec from Function App..."
OPENAPI_FILE=$(mktemp)
trap 'rm -f "${OPENAPI_FILE}"' EXIT

if ! curl -s -f "https://${FUNCTION_URL}/api/v1/openapi.json" \
  -o "${OPENAPI_FILE}"; then
  log_error "Failed to download OpenAPI spec from Function App"
  log_error "Ensure Function App is deployed and healthy"
  exit 1
fi

log_info "✓ OpenAPI spec downloaded"

# Check if API already exists
if az apim api show \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${API_PATH}" &>/dev/null; then
  log_info "API ${API_PATH} already exists, updating..."

  # Update existing API
  az apim api import \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --api-id "${API_PATH}" \
    --path "${API_PATH}" \
    --specification-format OpenApi \
    --specification-path "${OPENAPI_FILE}" \
    --service-url "https://${FUNCTION_URL}" \
    --output none

  log_info "✓ API updated from OpenAPI spec"
else
  log_info "Importing API from OpenAPI spec..."

  # Import new API
  az apim api import \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --api-id "${API_PATH}" \
    --path "${API_PATH}" \
    --display-name "${API_DISPLAY_NAME}" \
    --specification-format OpenApi \
    --specification-path "${OPENAPI_FILE}" \
    --service-url "https://${FUNCTION_URL}" \
    --protocols https \
    --subscription-required true \
    --output none

  log_info "✓ API imported from OpenAPI spec"
fi

# Get APIM gateway URL
APIM_GATEWAY=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query gatewayUrl -o tsv)

log_info ""
log_info "✓ APIM Backend Configuration Complete!"
log_info ""
log_info "API Details:"
log_info "  API Path: /${API_PATH}"
log_info "  Backend: https://${FUNCTION_URL}"
log_info "  APIM Gateway: ${APIM_GATEWAY}/${API_PATH}"
log_info ""
log_info "API Endpoints:"
log_info "  Health: ${APIM_GATEWAY}/${API_PATH}/api/v1/health"
log_info "  Docs: ${APIM_GATEWAY}/${API_PATH}/api/v1/docs"
log_info "  OpenAPI: ${APIM_GATEWAY}/${API_PATH}/api/v1/openapi.json"
log_info ""
log_info "Next Steps:"
log_info "  1. Apply policies: ./32-apim-policies.sh"
log_info "  2. Test API (will need subscription key after policies applied)"
log_info ""
log_warn "Note: API requires subscription key by default"
log_warn "Configure policies in step 32 to enable access"
