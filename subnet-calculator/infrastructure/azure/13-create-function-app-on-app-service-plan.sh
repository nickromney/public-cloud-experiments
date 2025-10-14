#!/usr/bin/env bash
#
# Create Azure Function App on App Service Plan
# - Creates a new Function App on an existing App Service Plan (not Consumption)
# - Requires: App Service Plan (create with 12-create-app-service-plan.sh)
# - Runtime: Python 3.11
# - Functions version: 4
# - OS: Linux
# - Idempotent: checks if function exists on specified plan
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
    az group list --query "[].[name,location]" -o tsv | awk '{printf "  - %s (%s)\n", $1, $2}'
    read -r -p "Enter resource group name: " RESOURCE_GROUP
    if [[ -z "${RESOURCE_GROUP}" ]]; then
      log_error "Resource group name is required"
      exit 1
    fi
  fi
fi

# Auto-detect or prompt for APP_SERVICE_PLAN
if [[ -z "${APP_SERVICE_PLAN:-}" ]]; then
  log_info "APP_SERVICE_PLAN not set. Looking for App Service Plans in ${RESOURCE_GROUP}..."
  PLAN_COUNT=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${PLAN_COUNT}" -eq 0 ]]; then
    log_error "No App Service Plans found in ${RESOURCE_GROUP}"
    log_error "Create one first with: ./12-create-app-service-plan.sh"
    exit 1
  elif [[ "${PLAN_COUNT}" -eq 1 ]]; then
    APP_SERVICE_PLAN=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    PLAN_SKU=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.name" -o tsv)
    PLAN_TIER=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.tier" -o tsv)
    log_info "Found App Service Plan: ${APP_SERVICE_PLAN} (${PLAN_SKU}/${PLAN_TIER})"
    read -r -p "Use this App Service Plan? (Y/n): " use_plan
    use_plan=${use_plan:-y}
    if [[ ! "${use_plan}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_info "Found ${PLAN_COUNT} App Service Plans in ${RESOURCE_GROUP}:"
    az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[].[name,sku.name,sku.tier]" -o tsv | \
      awk '{printf "  - %s (%s/%s)\n", $1, $2, $3}'
    read -r -p "Enter App Service Plan name: " APP_SERVICE_PLAN
    if [[ -z "${APP_SERVICE_PLAN}" ]]; then
      log_error "App Service Plan name is required"
      exit 1
    fi
  fi
fi

# Generate FUNCTION_APP_NAME if not set
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  RANDOM_SUFFIX=$(date +%s | tail -c 6)
  FUNCTION_APP_NAME="func-subnet-calc-asp-${RANDOM_SUFFIX}"
  log_info "FUNCTION_APP_NAME not set. Generated: ${FUNCTION_APP_NAME}"
fi

# Configuration with defaults
readonly STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stsubnetcalcasp$(date +%s | tail -c 6)}"
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
log_info "  Function App Name: ${FUNCTION_APP_NAME}"
log_info "  App Service Plan: ${APP_SERVICE_PLAN}"
log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "  Python Version: ${PYTHON_VERSION}"

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group ${RESOURCE_GROUP} not found"
  log_error "Create the resource group first or set correct RESOURCE_GROUP variable"
  exit 1
fi

# Verify App Service Plan exists
if ! az appservice plan show --name "${APP_SERVICE_PLAN}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "App Service Plan ${APP_SERVICE_PLAN} not found in resource group ${RESOURCE_GROUP}"
  log_error "Create the plan first using: ./12-create-app-service-plan.sh"
  exit 1
fi

# Get App Service Plan details
PLAN_SKU=$(az appservice plan show \
  --name "${APP_SERVICE_PLAN}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.name" \
  -o tsv)

PLAN_TIER=$(az appservice plan show \
  --name "${APP_SERVICE_PLAN}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.tier" \
  -o tsv)

log_info "App Service Plan found: ${APP_SERVICE_PLAN} (SKU: ${PLAN_SKU}, Tier: ${PLAN_TIER})"

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

  # Get existing plan name
  EXISTING_PLAN=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "appServicePlanId" \
    -o tsv | awk -F'/' '{print $NF}')

  if [[ "${EXISTING_PLAN}" == "${APP_SERVICE_PLAN}" ]]; then
    log_warn "Function App ${FUNCTION_APP_NAME} already exists on plan ${APP_SERVICE_PLAN}"
    log_info "Skipping creation (idempotent)"
  else
    log_error "Function App ${FUNCTION_APP_NAME} already exists on different plan"
    log_error "  Existing Plan: ${EXISTING_PLAN}"
    log_error "  Requested Plan: ${APP_SERVICE_PLAN}"
    log_error ""
    log_error "Options:"
    log_error "  1. Use different function name: FUNCTION_APP_NAME=\"func-new\" ./13-create-function-app-on-app-service-plan.sh"
    log_error "  2. Delete existing function: az functionapp delete --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi

  # Get hostname for output
  HOSTNAME=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query defaultHostName -o tsv)

  log_info ""
  log_info "Existing Function App details:"
  log_info "  Name: ${FUNCTION_APP_NAME}"
  log_info "  URL: https://${HOSTNAME}"
  log_info "  Plan: ${EXISTING_PLAN}"

  exit 0
fi

# Create Function App on App Service Plan
log_info "Creating Function App ${FUNCTION_APP_NAME} on plan ${APP_SERVICE_PLAN}..."
az functionapp create \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --plan "${APP_SERVICE_PLAN}" \
  --storage-account "${STORAGE_ACCOUNT_NAME}" \
  --runtime python \
  --runtime-version "${PYTHON_VERSION}" \
  --functions-version 4 \
  --os-type Linux \
  --disable-app-insights \
  --output none

log_info "Function App created successfully"

# Configure CORS to allow all origins (for development)
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

# Set basic app settings (testing configuration)
log_info "Configuring app settings for testing..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    DISABLE_AUTH=true \
  --output none

# Get Function App details for output
HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv)

FUNCTION_APP_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info ""
log_info "========================================="
log_info "Function App created successfully!"
log_info "========================================="
log_info ""
log_info "Function App: ${FUNCTION_APP_NAME}"
log_info "  URL: https://${HOSTNAME}"
log_info "  Runtime: Python ${PYTHON_VERSION}"
log_info "  Plan: ${APP_SERVICE_PLAN} (${PLAN_SKU} - ${PLAN_TIER})"
log_info "  Storage: ${STORAGE_ACCOUNT_NAME}"
log_info "  Resource ID: ${FUNCTION_APP_ID}"
log_info ""
log_info "Configuration:"
log_info "  CORS: Configured to allow all origins (*)"
log_info "  HTTPS Only: Enabled"
log_info "  Authentication: Disabled (DISABLE_AUTH=true)"
log_info ""
log_info "Next steps:"
log_info "  1. Deploy your function code using: 21-deploy-function.sh"
log_info "  2. Access API docs at: https://${HOSTNAME}/api/v1/docs"
log_info ""
log_info "To verify the function is on the correct plan:"
log_info "  az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} \\"
log_info "    --query '{name:name,plan:serverFarmId}' -o json"
log_info ""
