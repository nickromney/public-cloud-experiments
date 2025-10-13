#!/usr/bin/env bash
#
# Configure Azure API Management backend for Function App
# - Imports API from Function App OpenAPI spec
# - Creates backend pointing to Function App
# - Sets up API paths and operations
# - Verifies health endpoint connectivity

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP environment variable is required}"
readonly APIM_NAME="${APIM_NAME:?APIM_NAME environment variable is required}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:?FUNCTION_APP_NAME environment variable is required}"
readonly API_PATH="${API_PATH:-subnet-calc}"  # URL path: /subnet-calc/api/v1/*
readonly API_DISPLAY_NAME="${API_DISPLAY_NAME:-Subnet Calculator API}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

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
  --query defaultHostName -o tsv)

log_info "Function App URL: https://${FUNCTION_URL}"

# Check if backend already exists
BACKEND_ID="${FUNCTION_APP_NAME}-backend"
if az apim backend show \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --backend-id "${BACKEND_ID}" &>/dev/null; then
  log_info "Backend ${BACKEND_ID} already exists, updating..."
else
  log_info "Creating backend ${BACKEND_ID}..."
fi

# Create or update backend
az apim backend create \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --backend-id "${BACKEND_ID}" \
  --url "https://${FUNCTION_URL}" \
  --protocol http \
  --title "Subnet Calculator Function App" \
  --description "Backend for subnet calculator API" \
  --output none

log_info "✓ Backend created/updated"

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

# Set backend for all operations
log_info "Configuring backend for all operations..."

az apim api update \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${API_PATH}" \
  --service-url "https://${FUNCTION_URL}" \
  --output none

log_info "✓ Backend configured"

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
