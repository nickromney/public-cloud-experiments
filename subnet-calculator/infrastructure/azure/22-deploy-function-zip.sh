#!/usr/bin/env bash
#
# Deploy Function App using Azure CLI zip deployment
# - Avoids Python version mismatch issues with func CLI
# - Uses az functionapp deployment source config-zip
# - Requires Function App to already exist (created by 10-function-app.sh)
#
# Usage:
#   RESOURCE_GROUP="xxx" FUNCTION_APP_NAME="func-xxx" ./22-deploy-function-zip.sh
#   RESOURCE_GROUP="xxx" FUNCTION_APP_NAME="func-xxx" DISABLE_AUTH=true ./22-deploy-function-zip.sh

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory and source location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/../../api-fastapi-azure-function"

# Source selection utilities
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
    log_error "No resource groups found in subscription"
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

# Auto-detect or prompt for FUNCTION_APP_NAME
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  log_info "FUNCTION_APP_NAME not set. Checking for existing Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in resource group ${RESOURCE_GROUP}"
    log_error "Run 10-function-app.sh first to create one"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected single Function App: ${FUNCTION_APP_NAME}"
  else
    log_warn "Multiple Function Apps found:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

# Configuration with defaults
readonly DISABLE_AUTH="${DISABLE_AUTH:-false}"

# Verify Function App exists
if ! az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found in resource group ${RESOURCE_GROUP}"
  log_error "Run 10-function-app.sh first to create it"
  exit 1
fi

# Verify source directory exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  log_error "Source directory not found: ${SOURCE_DIR}"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Source: ${SOURCE_DIR}"
log_info "  Authentication: $([ "${DISABLE_AUTH}" = "true" ] && echo "Disabled" || echo "Enabled")"

# Configure application settings
log_info "Configuring application settings..."

if [ "${DISABLE_AUTH}" = "true" ]; then
  log_warn "Disabling authentication - API will be publicly accessible"
  az functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings AUTH_METHOD=none \
    --output none
else
  log_info "Authentication will be enabled (default JWT)"
fi

# Create temporary directory for deployment package
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

log_info "Preparing deployment package..."

# Copy function code
log_info "Copying function code..."
cp -r "${SOURCE_DIR}"/* "${TEMP_DIR}/"

# Remove unnecessary files
rm -rf "${TEMP_DIR}/.venv" "${TEMP_DIR}/__pycache__" "${TEMP_DIR}/.pytest_cache" "${TEMP_DIR}/tests" 2>/dev/null || true

# Create deployment package
DEPLOY_ZIP="${TEMP_DIR}/deploy.zip"
log_info "Creating deployment package..."
(cd "${TEMP_DIR}" && zip -r "${DEPLOY_ZIP}" . -x "*.pyc" -x "__pycache__/*" -x ".venv/*" -q)

# Deploy using Azure CLI
log_info "Deploying to Azure Function App using Azure CLI..."
log_info "This may take 2-3 minutes for remote build to complete..."

az functionapp deployment source config-zip \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --src "${DEPLOY_ZIP}" \
  --build-remote true \
  --timeout 600

log_info "Waiting for deployment to complete (30 seconds)..."
sleep 30

# Get Function App URL
FUNCTION_APP_URL="https://$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)"

log_info ""
log_info "========================================="
log_info "Function App deployed successfully!"
log_info "========================================="
log_info "Function App: ${FUNCTION_APP_NAME}"
log_info "URL: ${FUNCTION_APP_URL}"
log_info ""
log_info "API Endpoints:"
log_info "  Health:       ${FUNCTION_APP_URL}/api/v1/health"
log_info "  API Docs:     ${FUNCTION_APP_URL}/api/v1/docs"
log_info "  OpenAPI JSON: ${FUNCTION_APP_URL}/api/v1/openapi.json"
log_info ""
log_info "Test the API:"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info ""

# Test health endpoint
log_info "Testing health endpoint..."
if curl -f -s "${FUNCTION_APP_URL}/api/v1/health" &>/dev/null; then
  log_info "Health check: OK"
  curl -s "${FUNCTION_APP_URL}/api/v1/health" | python3 -m json.tool 2>/dev/null || echo ""
else
  log_warn "Health check failed - Function App may still be starting up"
  log_warn "Wait 1-2 minutes and try: curl ${FUNCTION_APP_URL}/api/v1/health"
fi

log_info ""
log_info "Next steps:"
log_info "1. Wait 1-2 minutes for Function App to fully start"
log_info "2. Test API: curl ${FUNCTION_APP_URL}/api/v1/health"
log_info "3. View logs: az functionapp log tail --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}"
log_info "4. Deploy frontend with: FRONTEND=typescript API_URL=${FUNCTION_APP_URL} ./20-deploy-frontend.sh"
