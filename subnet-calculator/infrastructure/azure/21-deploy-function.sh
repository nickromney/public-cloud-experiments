#!/usr/bin/env bash
#
# Deploy Function API to Azure Function App
# - Deploys the api-fastapi-azure-function code
# - Uses zip deployment for fast, reliable deploys
# - Configures necessary app settings
#
# Usage:
#   ./21-deploy-function.sh
#   DISABLE_AUTH=true ./21-deploy-function.sh  # Disable JWT authentication

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FUNCTION_DIR="${PROJECT_ROOT}/subnet-calculator/api-fastapi-azure-function"

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

# Check if Function App exists
if ! az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found"
  log_error "Run 10-function-app.sh first to create it"
  exit 1
fi

# Check if function directory exists
if [[ ! -d "${FUNCTION_DIR}" ]]; then
  log_error "Function directory not found: ${FUNCTION_DIR}"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Source: ${FUNCTION_DIR}"
log_info "  Authentication: $(if [[ "${DISABLE_AUTH}" == "true" ]]; then echo "Disabled"; else echo "Enabled (JWT)"; fi)"

# Get Function App URL
FUNCTION_URL=$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

# Configure app settings
log_info "Configuring application settings..."

if [[ "${DISABLE_AUTH}" == "true" ]]; then
  # Disable authentication
  log_warn "Disabling authentication - API will be publicly accessible"
  az functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings \
      "AUTH_METHOD=none" \
      "PYTHONUNBUFFERED=1" \
      "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
    --output none
else
  # Enable JWT authentication (requires JWT_SECRET_KEY to be set)
  log_info "JWT authentication enabled - you'll need to set JWT_SECRET_KEY"
  log_warn "To set JWT secret, run:"
  log_warn "  az functionapp config appsettings set \\"
  log_warn "    --name ${FUNCTION_APP_NAME} \\"
  log_warn "    --resource-group ${RESOURCE_GROUP} \\"
  log_warn "    --settings JWT_SECRET_KEY='your-secret-key-here'"

  az functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings \
      "AUTH_METHOD=jwt" \
      "JWT_ALGORITHM=HS256" \
      "PYTHONUNBUFFERED=1" \
      "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
    --output none
fi

# Build deployment package
log_info "Preparing deployment package..."
cd "${FUNCTION_DIR}"

# Create temporary deployment directory
DEPLOY_DIR=$(mktemp -d)
trap 'rm -rf "${DEPLOY_DIR}"' EXIT

# Copy function code
log_info "Copying function code..."
cp -r . "${DEPLOY_DIR}/"

# Remove development files
cd "${DEPLOY_DIR}"
rm -rf .venv __pycache__ .pytest_cache .ruff_cache tests/ test_*.py .vscode/ .claude/

# Ensure requirements.txt exists (Azure Functions needs this)
if [[ ! -f "requirements.txt" ]]; then
  log_info "Generating requirements.txt from pyproject.toml..."
  if command -v uv &>/dev/null; then
    uv pip compile pyproject.toml -o requirements.txt
  else
    log_error "uv not found and requirements.txt missing"
    log_error "Either install uv or create requirements.txt manually"
    exit 1
  fi
fi

# Create zip file
log_info "Creating deployment package..."
ZIP_FILE=$(mktemp).zip
zip -r "${ZIP_FILE}" . -q

# Deploy to Azure using func CLI for proper Python v2 support
log_info "Deploying to Azure Function App using func CLI..."
cd "${FUNCTION_DIR}"
func azure functionapp publish "${FUNCTION_APP_NAME}" --python

log_info "Deployment initiated. Waiting for deployment to complete..."
sleep 10

# Check deployment status
log_info "Checking deployment status..."
DEPLOYMENT_STATUS=$(az functionapp deployment list \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].status" -o tsv 2>/dev/null || echo "unknown")

if [[ "${DEPLOYMENT_STATUS}" == "4" ]] || [[ "${DEPLOYMENT_STATUS}" == "Success" ]]; then
  log_info "Deployment completed successfully"
else
  log_warn "Deployment status: ${DEPLOYMENT_STATUS} (may still be in progress)"
  log_warn "Check Azure portal for details if issues occur"
fi

# Restart function app to ensure new code is loaded
log_info "Restarting Function App to apply changes..."
az functionapp restart \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output none

log_info "Waiting for Function App to start..."
sleep 15

log_info ""
log_info "========================================="
log_info "Function API deployed successfully!"
log_info "========================================="
log_info "Function App: ${FUNCTION_APP_NAME}"
log_info "API URL: https://${FUNCTION_URL}"
log_info "API Docs: https://${FUNCTION_URL}/api/v1/docs"
log_info "Health Check: https://${FUNCTION_URL}/api/v1/health"
log_info ""
if [[ "${DISABLE_AUTH}" == "true" ]]; then
  log_info "Authentication: DISABLED (public access)"
else
  log_info "Authentication: JWT (requires token)"
  log_info ""
  log_warn "Don't forget to set JWT_SECRET_KEY in app settings!"
fi
log_info ""
log_info "Test the API:"
log_info "  curl https://${FUNCTION_URL}/api/v1/health"
log_info ""
log_info "To view logs:"
log_info "  az functionapp log tail --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}"
