#!/usr/bin/env bash
#
# Create Azure Function App for subnet calculator API
# - Plan: Consumption Flex (cheapest serverless option)
# - Runtime: Python 3.11
# - No authentication initially (public access)
# - Works in sandbox environments (pre-existing resource group)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stsubnetcalc$(date +%s | tail -c 6)}"
# Add random suffix to function name to ensure uniqueness
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-${RANDOM_SUFFIX}}"
readonly PYTHON_VERSION="${PYTHON_VERSION:-3.11}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory (reserved for future use)
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected location from resource group: ${LOCATION}"
  else
    log_error "Resource group ${RESOURCE_GROUP} not found and LOCATION not set"
    log_error "Either create the resource group first or set LOCATION environment variable"
    exit 1
  fi
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "  Function App Name: ${FUNCTION_APP_NAME}"
log_info "  Python Version: ${PYTHON_VERSION}"

# Create or verify resource group
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating resource group ${RESOURCE_GROUP}..."
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
else
  log_info "Resource group ${RESOURCE_GROUP} already exists"
fi

# Check if storage account already exists
if az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
else
  # Create storage account (required for Function Apps)
  log_info "Creating storage account ${STORAGE_ACCOUNT_NAME}..."
  az storage account create \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --output none

  log_info "Storage account created successfully"
fi

# Check if Function App already exists
if az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "Function App ${FUNCTION_APP_NAME} already exists"

  # Get hostname
  HOSTNAME=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query defaultHostName -o tsv)

  log_info "Existing Function App details:"
  log_info "  URL: https://${HOSTNAME}"

  exit 0
fi

# Create Function App with Consumption Flex plan
log_info "Creating Function App ${FUNCTION_APP_NAME}..."
az functionapp create \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --storage-account "${STORAGE_ACCOUNT_NAME}" \
  --runtime python \
  --runtime-version "${PYTHON_VERSION}" \
  --functions-version 4 \
  --os-type Linux \
  --consumption-plan-location "${LOCATION}" \
  --disable-app-insights \
  --output none

log_info "Function App created successfully"

# Configure CORS to allow Static Web App access
log_info "Configuring CORS to allow all origins (for development)..."
az functionapp cors add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --allowed-origins "*" \
  --output none

# Enable HTTPS only
log_info "Enabling HTTPS only..."
az functionapp update \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --set httpsOnly=true \
  --output none

# Get hostname
HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv)

log_info ""
log_info "========================================="
log_info "Function App created successfully!"
log_info "========================================="
log_info "Name: ${FUNCTION_APP_NAME}"
log_info "URL: https://${HOSTNAME}"
log_info "Runtime: Python ${PYTHON_VERSION}"
log_info "Plan: Consumption (Serverless)"
log_info ""
log_info "CORS: Configured to allow all origins (*)"
log_info "HTTPS Only: Enabled"
log_info "Authentication: Disabled (public access)"
log_info ""
log_info "Next steps:"
log_info "1. Use 21-deploy-function.sh to deploy the API"
log_info "2. Access API docs at: https://${HOSTNAME}/api/v1/docs"
log_info ""
log_info "To get the Function App URL again, run:"
log_info "  az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --query defaultHostName -o tsv"
