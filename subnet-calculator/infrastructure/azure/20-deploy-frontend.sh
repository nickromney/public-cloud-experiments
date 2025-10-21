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
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GENERATED_DIR="${SCRIPT_DIR}/generated"

mkdir -p "${GENERATED_DIR}"

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

# Check if production environment already has a deployment
PRODUCTION_STATUS=$(az staticwebapp environment list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?name=='default'].status" -o tsv 2>/dev/null || echo "WaitingForDeployment")

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Frontend: ${FRONTEND}"
log_info "  Target URL: https://${SWA_URL}"
if [[ "${USE_APIM}" == "true" ]]; then
  log_info "  Using APIM: ${APIM_NAME}"
fi
if [[ -n "${API_URL}" ]]; then
  log_info "  API URL: ${API_URL}"
else
  log_info "  API URL: (SWA proxy pattern - relative URLs)"
fi
if [[ -n "${VITE_API_URL:-}" ]]; then
  log_info "  VITE_API_URL: ${VITE_API_URL}"
else
  log_info "  VITE_API_URL: (empty - SWA proxy pattern)"
fi
if [[ "${VITE_AUTH_ENABLED:-false}" == "true" ]]; then
  log_info "  Authentication: Entra ID enabled (VITE_AUTH_ENABLED=true)"
else
  log_info "  Authentication: disabled (VITE_AUTH_ENABLED=false or unset)"
fi

# If production environment already has a deployment, ask if user wants to redeploy
if [[ "${PRODUCTION_STATUS}" == "Ready" ]]; then
  log_info ""
  log_info "Production environment already has a deployment (status: Ready)."
  read -p "Redeploy frontend? (Y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    log_info "Skipping deployment - using existing frontend"
    log_info ""
    log_info "Frontend URL: https://${SWA_URL}"
    exit 0
  fi
fi

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
    # Preserve VITE_API_URL if already set, otherwise use API_URL
    if [[ -z "${VITE_API_URL:-}" ]]; then
      if [[ -n "${API_URL}" ]]; then
        log_info "Configuring API URL: ${API_URL}"
        export VITE_API_URL="${API_URL}"
      else
        log_info "Using SWA proxy pattern (empty API_URL)"
        export VITE_API_URL=""
      fi
    else
      log_info "Using pre-configured VITE_API_URL: ${VITE_API_URL}"
    fi

    # Clean previous build
    rm -rf dist

    # Build the app
    log_info "Building production bundle..."
    npm run build

    # Copy appropriate staticwebapp.config.json based on authentication mode
    log_step "Configuring Static Web App rules..."
    log_info "DEBUG: VITE_AUTH_ENABLED='${VITE_AUTH_ENABLED:-unset}'"
    log_info "DEBUG: SWA_AUTH_ENABLED='${SWA_AUTH_ENABLED:-unset}'"
    log_info "DEBUG: Current directory: $(pwd)"
    log_info "DEBUG: SCRIPT_DIR='${SCRIPT_DIR}'"
    log_info "DEBUG: dist directory exists: $([ -d dist ] && echo 'yes' || echo 'no')"

    # Determine which config file to use
    # SWA_AUTH_ENABLED controls SWA platform auth (Entra ID)
    # VITE_AUTH_ENABLED controls frontend JWT auth (separate from SWA)
    if [[ "${SWA_AUTH_ENABLED:-false}" == "true" ]]; then
      log_info "Using Entra ID authentication config (SWA built-in provider)"
      CONFIG_FILE="${SCRIPT_DIR}/staticwebapp-entraid-builtin.config.json"
    else
      # No SWA platform authentication (may still have frontend JWT auth)
      log_info "Using no-auth config (no SWA platform authentication)"
      CONFIG_FILE="${SCRIPT_DIR}/staticwebapp-noauth.config.json"
    fi

    # Copy the selected config file
    log_info "DEBUG: Source config file: ${CONFIG_FILE}"
    # Verify source file exists before copying using if.*-f test
    if [ -f "${CONFIG_FILE}" ]; then
      log_info "DEBUG: Source file exists: yes"
    else
      log_info "DEBUG: Source file exists: no"
    fi

    if ! cp "${CONFIG_FILE}" dist/staticwebapp.config.json; then
      log_error "Failed to copy config from ${CONFIG_FILE}"
      exit 1
    fi

    # Verify destination file was copied successfully using if.*-f test
    if [ -f dist/staticwebapp.config.json ]; then
      log_info "DEBUG: Destination file exists: yes"
      log_info "Config copied successfully to dist/staticwebapp.config.json"
    else
      log_info "DEBUG: Destination file exists: no"
      log_error "Config file missing after copy!"
    fi

    # If using Entra ID config, substitute AZURE_TENANT_ID placeholder
    if [[ "${SWA_AUTH_ENABLED:-false}" == "true" ]]; then
      log_step "Processing Entra ID configuration..."

      # Get tenant ID from Azure CLI
      if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
        log_info "AZURE_TENANT_ID not set. Detecting from Azure account..."
        AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
        if [[ -z "${AZURE_TENANT_ID}" ]]; then
          log_error "Failed to detect AZURE_TENANT_ID. Please set it explicitly."
          exit 1
        fi
        log_info "Detected AZURE_TENANT_ID: ${AZURE_TENANT_ID}"
      fi

      # Substitute AZURE_TENANT_ID placeholder in config file
      log_info "DEBUG: Substituting AZURE_TENANT_ID placeholder with ${AZURE_TENANT_ID}"
      if ! sed -i.bak "s/AZURE_TENANT_ID/${AZURE_TENANT_ID}/g" dist/staticwebapp.config.json; then
        log_error "Failed to substitute AZURE_TENANT_ID in config"
        exit 1
      fi

      # Verify substitution
      if grep -q "AZURE_TENANT_ID" dist/staticwebapp.config.json; then
        log_error "AZURE_TENANT_ID placeholder still present after substitution!"
        exit 1
      fi

      log_info "Entra ID configuration processed successfully"
      rm -f dist/staticwebapp.config.json.bak

      # Persist generated config for diagnostics and verification
      GENERATED_CONFIG="${GENERATED_DIR}/staticwebapp-entraid.${STATIC_WEB_APP_NAME}.staticwebapp.config.json"
      log_info "Saving generated config snapshot to ${GENERATED_CONFIG}"
      cp dist/staticwebapp.config.json "${GENERATED_CONFIG}"
    fi

    # Check if SWA CLI is installed
    if ! command -v swa &>/dev/null; then
      log_warn "Azure Static Web Apps CLI not found. Installing globally..."
      npm install -g @azure/static-web-apps-cli
    fi

    # Deploy to Static Web App
    log_info "Deploying to Azure Static Web App..."
    swa deploy \
      --app-location dist \
      --output-location . \
      --swa-config-location dist \
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
