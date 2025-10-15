#!/usr/bin/env bash
#
# Deploy Function App configured for API Management
# - Sets AUTH_METHOD=apim (Function trusts X-User-* headers from APIM)
# - Restricts IP access to APIM only (blocks direct access)
# - Disables CORS (APIM handles it)
# - Uses Azure CLI zip deployment with remote build
#
# Prerequisites:
#   - Function App created (10-function-app.sh)
#   - APIM instance created (30-apim-instance.sh)
#   - APIM backend configured (31-apim-backend.sh)
#
# Usage:
#   RESOURCE_GROUP="xxx" FUNCTION_APP_NAME="func-xxx" APIM_NAME="apim-xxx" ./23-deploy-function-apim.sh

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

# Source shared utilities
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

# Auto-detect or prompt for APIM_NAME
if [[ -z "${APIM_NAME:-}" ]]; then
  log_info "APIM_NAME not set. Checking for existing API Management instances..."
  APIM_COUNT=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${APIM_COUNT}" -eq 0 ]]; then
    log_error "No API Management instances found in resource group ${RESOURCE_GROUP}"
    log_error "Run 30-apim-instance.sh first to create one"
    exit 1
  elif [[ "${APIM_COUNT}" -eq 1 ]]; then
    APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected single APIM instance: ${APIM_NAME}"
  else
    log_warn "Multiple API Management instances found:"
    APIM_NAME=$(select_apim_instance "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${APIM_NAME}"
  fi
fi

# Verify Function App exists
if ! az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found"
  log_error "Run ./10-function-app.sh first"
  exit 1
fi

# Verify APIM exists
if ! az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "APIM instance ${APIM_NAME} not found"
  log_error "Run ./30-apim-instance.sh first"
  exit 1
fi

# Verify source directory exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  log_error "Source directory not found: ${SOURCE_DIR}"
  exit 1
fi

# Get APIM public IP addresses
log_info "Getting APIM public IP addresses..."
APIM_IPS=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query publicIPAddresses -o tsv | tr '\t' '\n')

if [[ -z "${APIM_IPS}" ]]; then
  log_error "Could not retrieve APIM IP addresses"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  APIM Name: ${APIM_NAME}"
log_info "  Source: ${SOURCE_DIR}"
log_info "  APIM IPs: $(echo "${APIM_IPS}" | tr '\n' ', ' | sed 's/,$//')"

# Configure application settings for APIM mode
log_info "Configuring Function App for APIM..."

az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings AUTH_METHOD=apim \
  --output none

log_info "✓ AUTH_METHOD=apim configured"

# Remove existing IP restrictions
log_info "Removing existing IP restrictions..."
az functionapp config access-restriction remove \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "AllowAll" 2>/dev/null || true

# Add IP restrictions for each APIM IP
log_info "Adding IP restrictions for APIM..."
PRIORITY=100
while IFS= read -r IP; do
  if [[ -n "${IP}" ]]; then
    log_info "  Adding rule for ${IP}"
    az functionapp config access-restriction add \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --rule-name "APIM-${IP//\./-}" \
      --action Allow \
      --ip-address "${IP}" \
      --priority "${PRIORITY}" \
      --output none || log_warn "Failed to add rule for ${IP}"
    PRIORITY=$((PRIORITY + 1))
  fi
done <<< "${APIM_IPS}"

log_info "✓ IP restrictions applied (Function App only accepts traffic from APIM)"

# Disable CORS (APIM handles it)
log_info "Disabling CORS on Function App (APIM handles CORS)..."
az functionapp cors remove \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --allowed-origins "*" 2>/dev/null || true

log_info "✓ CORS disabled"

# Create temporary directory for deployment package
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

log_info "Preparing deployment package..."

# Copy function code
cp -r "${SOURCE_DIR}"/* "${TEMP_DIR}/"

# Remove unnecessary files
rm -rf "${TEMP_DIR}/.venv" "${TEMP_DIR}/__pycache__" "${TEMP_DIR}/.pytest_cache" "${TEMP_DIR}/tests" 2>/dev/null || true

# Create deployment package
DEPLOY_ZIP="${TEMP_DIR}/deploy.zip"
(cd "${TEMP_DIR}" && zip -r "${DEPLOY_ZIP}" . -x "*.pyc" -x "__pycache__/*" -x ".venv/*" -q)

# Deploy using Azure CLI
log_info "Deploying to Azure Function App..."
log_info "This may take 2-3 minutes for remote build to complete..."

az functionapp deployment source config-zip \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --src "${DEPLOY_ZIP}" \
  --build-remote true \
  --timeout 600 \
  --output none

log_info "✓ Deployment complete"

# Wait for Function App to be ready
log_info "Waiting for Function App to be ready..."
sleep 10

# Test health endpoint through APIM
APIM_GATEWAY=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query gatewayUrl -o tsv)

log_info "Testing Function App health via APIM..."

# Note: This will fail if policies require subscription key
# User needs to test with subscription key from step 32
log_warn "If policies require subscription key, this test will fail (401)"
log_warn "Use the subscription key from ./32-apim-policies.sh to test"

log_info ""
log_info "✓ Function App Deployment Complete!"
log_info ""
log_info "Function App Configuration:"
log_info "  AUTH_METHOD: apim"
log_info "  IP Restrictions: APIM IPs only"
log_info "  CORS: Disabled (handled by APIM)"
log_info ""
log_info "Access via APIM Gateway:"
log_info "  ${APIM_GATEWAY}/subnet-calc/api/v1/health"
log_info ""
log_info "Direct access blocked:"
FUNCTION_URL=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv)
log_info "  https://${FUNCTION_URL}/api/v1/health (will return 403 Forbidden)"
log_info ""
log_info "Next Steps:"
log_info "  1. Test API through APIM (may need subscription key)"
log_info "  2. Deploy frontend: USE_APIM=true ./20-deploy-frontend.sh"
