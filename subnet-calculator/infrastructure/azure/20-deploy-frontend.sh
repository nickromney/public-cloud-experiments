#!/usr/bin/env bash
#
# Deploy frontend to Azure Static Web App
# Supports all 4 frontend options:
#   - flask (Flask + Jinja2)
#   - static (Static HTML + JS)
#   - typescript (TypeScript + Vite)
#
# Usage:
#   FRONTEND=typescript ./20-deploy-frontend.sh
#   FRONTEND=static API_URL=https://func-xyz.azurewebsites.net ./20-deploy-frontend.sh

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

# Auto-detect or prompt for STATIC_WEB_APP_NAME
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_info "STATIC_WEB_APP_NAME not set. Checking for existing Static Web Apps..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in resource group ${RESOURCE_GROUP}"
    log_error "Run 00-static-web-app.sh first to create one"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected single Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_warn "Multiple Static Web Apps found:"
    STATIC_WEB_APP_NAME=$(select_static_web_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
  fi
fi

# Configuration with defaults
readonly FRONTEND="${FRONTEND:-typescript}"
readonly USE_APIM="${USE_APIM:-false}"
readonly APIM_NAME="${APIM_NAME:-}"
readonly API_PATH="${API_PATH:-subnet-calc}"
API_URL="${API_URL:-}"

# Check if Static Web App exists
if ! az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found"
  log_error "Run 00-static-web-app.sh first to create it"
  exit 1
fi

# Validate frontend choice
case "${FRONTEND}" in
  flask|static|typescript)
    log_info "Selected frontend: ${FRONTEND}"
    ;;
  *)
    log_error "Invalid frontend: ${FRONTEND}"
    log_error "Valid options: flask, static, typescript"
    exit 1
    ;;
esac

# Handle APIM configuration
if [[ "${USE_APIM}" == "true" ]]; then
  if [[ -z "${APIM_NAME}" ]]; then
    log_error "APIM_NAME required when USE_APIM=true"
    exit 1
  fi

  # Verify APIM exists and get gateway URL
  if ! az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    log_error "APIM instance ${APIM_NAME} not found"
    log_error "Run ./30-apim-instance.sh first"
    exit 1
  fi

  APIM_GATEWAY=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query gatewayUrl -o tsv)

  # Calculate API URL from APIM gateway
  API_URL="${APIM_GATEWAY}/${API_PATH}"
  log_info "Using APIM gateway: ${API_URL}"
fi

# Get deployment token
log_info "Retrieving deployment token..."
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Get Static Web App URL
SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Frontend: ${FRONTEND}"
log_info "  Target URL: https://${SWA_URL}"
[[ "${USE_APIM}" == "true" ]] && log_info "  Using APIM: ${APIM_NAME}"
[[ -n "${API_URL}" ]] && log_info "  API URL: ${API_URL}"

# Deploy based on frontend type
case "${FRONTEND}" in
  typescript)
    FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
    log_info "Building TypeScript + Vite frontend..."

    cd "${FRONTEND_DIR}"

    # Install dependencies if needed
    if [[ ! -d "node_modules" ]]; then
      log_info "Installing npm dependencies..."
      npm install
    fi

    # Set API URL via environment variable for Vite
    if [[ -n "${API_URL}" ]]; then
      log_info "Configuring API URL: ${API_URL}"
      export VITE_API_URL="${API_URL}"
    fi

    # Build the app
    log_info "Building production bundle..."
    npm run build

    # Check if SWA CLI is installed
    if ! command -v swa &>/dev/null; then
      log_warn "Azure Static Web Apps CLI not found. Installing globally..."
      npm install -g @azure/static-web-apps-cli
    fi

    # Deploy to Static Web App
    log_info "Deploying to Azure Static Web App..."
    swa deploy \
      --app-location dist \
      --deployment-token "${DEPLOYMENT_TOKEN}" \
      --env production \
      --api-language node \
      --api-version 20

    ;;

  static)
    FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-html-static"
    log_info "Deploying static HTML + JS frontend..."

    cd "${FRONTEND_DIR}"

    # Update API URL in JavaScript if provided
    if [[ -n "${API_URL}" ]]; then
      log_info "Configuring API URL: ${API_URL}"
      sed -i.bak "s|http://localhost:8090|${API_URL}|g" js/app.js
    fi

    # Check if SWA CLI is installed
    if ! command -v swa &>/dev/null; then
      log_warn "Azure Static Web Apps CLI not found. Installing globally..."
      npm install -g @azure/static-web-apps-cli
    fi

    # Deploy to Static Web App
    log_info "Deploying to Azure Static Web App..."
    swa deploy \
      --app-location . \
      --deployment-token "${DEPLOYMENT_TOKEN}" \
      --env production \
      --api-language node \
      --api-version 20

    # Restore original file if we made changes
    if [[ -n "${API_URL}" ]] && [[ -f "js/app.js.bak" ]]; then
      mv js/app.js.bak js/app.js
    fi

    ;;

  flask)
    log_error "Flask frontend deployment to Static Web Apps not supported"
    log_error "Flask requires a server runtime, which Static Web Apps doesn't provide"
    log_error "Consider using:"
    log_error "  1. TypeScript Vite frontend (recommended)"
    log_error "  2. Static HTML frontend"
    log_error "  3. Deploy Flask to Azure App Service or Container Apps instead"
    exit 1
    ;;
esac

log_info ""
log_info "========================================="
log_info "Frontend deployed successfully!"
log_info "========================================="
log_info "Frontend: ${FRONTEND}"
log_info "URL: https://${SWA_URL}"
[[ -n "${API_URL}" ]] && log_info "API: ${API_URL}"
log_info ""
log_info "Visit your application at:"
log_info "  https://${SWA_URL}"
log_info ""
log_info "Note: Initial deployment may take 1-2 minutes to propagate"
