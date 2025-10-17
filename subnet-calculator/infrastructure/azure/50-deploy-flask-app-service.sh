#!/usr/bin/env bash
#
# Deploy Flask frontend to Azure App Service
# - Creates App Service with Python 3.11 runtime
# - Uses zip deployment (no containerization)
# - Configures environment variables for JWT authentication
# - Shares App Service Plan with Function App or creates new one
# - Works in sandbox environments (pre-existing resource group)
#
# Usage:
#   RESOURCE_GROUP="xxx" FUNCTION_APP_NAME="func-xxx" ./50-deploy-flask-app-service.sh
#   RESOURCE_GROUP="xxx" API_BASE_URL="https://func-xxx.azurewebsites.net" ./50-deploy-flask-app-service.sh

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
SOURCE_DIR="${SCRIPT_DIR}/../../frontend-python-flask"

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

# Detect location from resource group
LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)

# Configuration with defaults
readonly APP_SERVICE_NAME="${APP_SERVICE_NAME:-app-flask-subnet-calc}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-}"
readonly PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
readonly JWT_USERNAME="${JWT_USERNAME:-admin}"
readonly JWT_PASSWORD="${JWT_PASSWORD:-subnet-calc-2024}"
readonly JWT_SECRET_KEY="${JWT_SECRET_KEY:-$(openssl rand -base64 32)}"
readonly JWT_ALGORITHM="${JWT_ALGORITHM:-HS256}"

# Get API URL - either from FUNCTION_APP_NAME or API_BASE_URL
if [[ -z "${API_BASE_URL:-}" ]]; then
  if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
    log_warn "Neither API_BASE_URL nor FUNCTION_APP_NAME set. Looking for Function Apps..."
    FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "${FUNC_COUNT}" -eq 1 ]]; then
      FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
      API_BASE_URL="https://$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.defaultHostName" -o tsv)"
      log_info "Auto-detected Function App: ${FUNCTION_APP_NAME}"
      log_info "API URL: ${API_BASE_URL}"
    elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
      log_warn "Multiple Function Apps found:"
      FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
      log_info "Selected: ${FUNCTION_APP_NAME}"
      API_BASE_URL="https://$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.defaultHostName" -o tsv)"
    else
      log_error "No Function App found and API_BASE_URL not set"
      log_error "Either set API_BASE_URL or create a Function App first"
      exit 1
    fi
  else
    API_BASE_URL="https://$(az functionapp show \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "properties.defaultHostName" -o tsv)"
  fi
fi

# Verify source directory exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  log_error "Flask source directory not found: ${SOURCE_DIR}"
  exit 1
fi

# Verify Flask app exists
if [[ ! -f "${SOURCE_DIR}/app.py" ]]; then
  log_error "Flask app.py not found in ${SOURCE_DIR}"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  App Service Name: ${APP_SERVICE_NAME}"
log_info "  Python Version: ${PYTHON_VERSION}"
log_info "  API Base URL: ${API_BASE_URL}"
log_info "  JWT Username: ${JWT_USERNAME}"

# Find or create App Service Plan
if [[ -z "${APP_SERVICE_PLAN_NAME}" ]]; then
  log_info "Looking for existing App Service Plans..."
  PLAN_COUNT=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${PLAN_COUNT}" -eq 1 ]]; then
    APP_SERVICE_PLAN_NAME=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    PLAN_SKU=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.name" -o tsv)
    log_info "Found existing App Service Plan: ${APP_SERVICE_PLAN_NAME} (${PLAN_SKU})"
    log_info "Reusing this plan to avoid additional costs"
  elif [[ "${PLAN_COUNT}" -gt 1 ]]; then
    log_warn "Multiple App Service Plans found:"
    # Build array for selection (allow empty selection to create new)
    plan_items=()
    while IFS=$'\t' read -r name sku; do
      plan_items+=("${name} (${sku})")
    done < <(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[].[name,sku.name]" -o tsv)

    # Display plans
    i=1
    for item in "${plan_items[@]}"; do
      echo "  ${i}. ${item}"
      ((i++))
    done
    echo ""

    read -r -p "Enter App Service Plan (1-${#plan_items[@]}) or name (press Enter to create new): " plan_selection

    if [[ -n "${plan_selection}" ]]; then
      if [[ "${plan_selection}" =~ ^[0-9]+$ ]]; then
        if [[ "${plan_selection}" -ge 1 && "${plan_selection}" -le "${#plan_items[@]}" ]]; then
          APP_SERVICE_PLAN_NAME=$(echo "${plan_items[$((plan_selection - 1))]}" | awk '{print $1}')
          log_info "Selected: ${APP_SERVICE_PLAN_NAME}"
        else
          log_error "Invalid selection"
          exit 1
        fi
      else
        APP_SERVICE_PLAN_NAME="${plan_selection}"
      fi
    fi
  fi
fi

# Create App Service Plan if needed
if [[ -z "${APP_SERVICE_PLAN_NAME}" ]]; then
  APP_SERVICE_PLAN_NAME="plan-flask-subnet-calc"
  log_info "Creating App Service Plan: ${APP_SERVICE_PLAN_NAME} (F1 Free tier)..."

  az appservice plan create \
    --name "${APP_SERVICE_PLAN_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku F1 \
    --is-linux \
    --output none

  log_info "App Service Plan created successfully"
else
  log_info "Using existing App Service Plan: ${APP_SERVICE_PLAN_NAME}"
fi

# Check if App Service already exists
if az webapp show \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "App Service ${APP_SERVICE_NAME} already exists"

  read -r -p "Update existing App Service? (Y/n): " update_existing
  update_existing=${update_existing:-y}

  if [[ ! "${update_existing}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled"
    exit 0
  fi
else
  # Create App Service
  log_info "Creating App Service ${APP_SERVICE_NAME}..."
  az webapp create \
    --name "${APP_SERVICE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --plan "${APP_SERVICE_PLAN_NAME}" \
    --runtime "PYTHON:${PYTHON_VERSION}" \
    --output none

  log_info "App Service created successfully"
fi

# Configure environment variables
log_info "Configuring environment variables..."
az webapp config appsettings set \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    API_BASE_URL="${API_BASE_URL}" \
    JWT_USERNAME="${JWT_USERNAME}" \
    JWT_PASSWORD="${JWT_PASSWORD}" \
    JWT_SECRET_KEY="${JWT_SECRET_KEY}" \
    JWT_ALGORITHM="${JWT_ALGORITHM}" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
  --output none

# Configure startup command for gunicorn
log_info "Configuring startup command..."
az webapp config set \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --startup-file "gunicorn --bind=0.0.0.0 --timeout 600 app:app" \
  --output none

# Enable HTTPS only
log_info "Enabling HTTPS only..."
az webapp update \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --set httpsOnly=true \
  --output none

# Create deployment package
log_info "Creating deployment package..."
TEMP_DIR=$(mktemp -d)
cd "${SOURCE_DIR}"

# Copy application files
cp -r . "${TEMP_DIR}/"

# Generate requirements.txt from pyproject.toml if needed
if [[ ! -f "${TEMP_DIR}/requirements.txt" ]]; then
  log_info "Generating requirements.txt from pyproject.toml..."
  if command -v uv &>/dev/null; then
    cd "${TEMP_DIR}"
    uv pip compile pyproject.toml -o requirements.txt
  else
    log_warn "uv not found, creating minimal requirements.txt"
    cat > "${TEMP_DIR}/requirements.txt" <<EOF
flask>=3.1.2
gunicorn>=23.0.0
requests>=2.32.5
EOF
  fi
fi

# Create zip file (excluding development files for security)
# NOTE: Review this exclusion list when adding new development files
ZIP_FILE="${TEMP_DIR}/deploy.zip"
cd "${TEMP_DIR}"
zip -r "${ZIP_FILE}" . \
  -x "*.pyc" \
  -x "__pycache__/*" \
  -x ".pytest_cache/*" \
  -x ".ruff_cache/*" \
  -x ".venv/*" \
  -x "*.git/*" \
  -x "compose.yml" \
  -x "Dockerfile" \
  -x ".dockerignore" \
  -x "test_*.py" \
  -x "conftest.py" \
  -x "Makefile" \
  -x "*.md" \
  -x "uv.lock" \
  -x "pyproject.toml" \
  > /dev/null

log_info "Deployment package created: ${ZIP_FILE}"

# Deploy to App Service
log_info "Deploying to App Service..."
az webapp deployment source config-zip \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --src "${ZIP_FILE}" \
  --output none

# Cleanup
rm -rf "${TEMP_DIR}"

# Get App Service URL
APP_SERVICE_URL="https://$(az webapp show \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.defaultHostName" -o tsv)"

log_info ""
log_info "========================================="
log_info "Flask App Service deployed successfully!"
log_info "========================================="
log_info "Name: ${APP_SERVICE_NAME}"
log_info "URL: ${APP_SERVICE_URL}"
log_info "Runtime: Python ${PYTHON_VERSION}"
log_info "Plan: ${APP_SERVICE_PLAN_NAME}"
log_info ""
log_info "Configuration:"
log_info "  API Base URL: ${API_BASE_URL}"
log_info "  JWT Username: ${JWT_USERNAME}"
log_info "  JWT Password: ${JWT_PASSWORD}"
log_info "  JWT Algorithm: ${JWT_ALGORITHM}"
log_info ""
log_info "Login credentials:"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info ""
log_info "Note: Deployment may take 1-2 minutes to complete."
log_info "      The app will be automatically started after deployment."
log_info ""
log_info "Test commands:"
log_info "  # Open Flask frontend"
log_info "  open ${APP_SERVICE_URL}"
log_info ""
log_info "  # Check app logs"
log_info "  az webapp log tail --name ${APP_SERVICE_NAME} --resource-group ${RESOURCE_GROUP}"
log_info ""
