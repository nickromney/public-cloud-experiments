#!/usr/bin/env bash
#
# Create Azure Function App for subnet calculator API
# - Plan: Consumption Flex (cheapest serverless option)
# - Runtime: Python 3.11
# - No authentication initially (public access)
# - Works in sandbox environments (pre-existing resource group)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Source selection utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    log_error "Create one with: az group create --name rg-subnet-calc --location eastus"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    RG_LOCATION=$(az group list --query "[0].location" -o tsv)
    log_info "Found single resource group: ${RESOURCE_GROUP} (${RG_LOCATION})"
    log_info "This appears to be a sandbox or constrained environment."
    read -r -p "Use this resource group? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Check for existing Function Apps (informational only - multiple allowed)
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    EXISTING_FUNC_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_FUNC_URL=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].defaultHostName" -o tsv)

    log_info "Found existing Function App: ${EXISTING_FUNC_NAME}"
    log_info "  URL: https://${EXISTING_FUNC_URL}"
    log_info ""
    log_info "Note: Multiple Function Apps are allowed in the same resource group."
    log_info "      Useful for different services (api, worker, processor, etc.)"
    log_info ""
    read -r -p "Use existing Function App? (Y/n): " use_existing
    use_existing=${use_existing:-y}

    if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
      FUNCTION_APP_NAME="${EXISTING_FUNC_NAME}"

      log_info ""
      log_info "✓ Using existing Function App"
      log_info ""
      log_info "Function App Details:"
      log_info "  Name: ${FUNCTION_APP_NAME}"
      log_info "  URL: https://${EXISTING_FUNC_URL}"
      log_info ""
      log_info "Next steps:"
      log_info "  1. Deploy code: ./21-deploy-function.sh"
      exit 0
    else
      log_info "Creating new Function App alongside existing one..."
    fi
  elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
    log_info "Found ${FUNC_COUNT} existing Function Apps in ${RESOURCE_GROUP}:"
    az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].[name,defaultHostName]" -o tsv | \
      awk '{printf "  - %s (https://%s)\n", $1, $2}'
    log_info ""
    log_info "Multiple Function Apps are normal for complex applications."
    log_info "Creating new Function App with unique name..."
  fi
fi

# Configuration with defaults (generate random suffix if not set)
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
readonly STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stsubnetcalc$(date +%s | tail -c 6)}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-${RANDOM_SUFFIX}}"
readonly PYTHON_VERSION="${PYTHON_VERSION:-3.11}"

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

# Create Function App with Flex Consumption plan
# Flex Consumption (replaces deprecated Y1 Linux Consumption)
# - Same free tier: 1M requests/month, 400k GB-s execution
# - Better performance: faster cold starts, advanced networking
# - Default: 2048 MB memory per instance
log_info "Creating Function App ${FUNCTION_APP_NAME} with Flex Consumption..."
az functionapp create \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --storage-account "${STORAGE_ACCOUNT_NAME}" \
  --runtime python \
  --runtime-version "${PYTHON_VERSION}" \
  --functions-version 4 \
  --flexconsumption-location "${LOCATION}" \
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
log_info "Plan: Flex Consumption (Serverless)"
log_info "Memory: 2048 MB per instance (default)"
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
