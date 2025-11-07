#!/usr/bin/env bash
#
# 59-deploy-typescript-app-service.sh
# Build the Vite TypeScript frontend and deploy it to an Azure App Service (Linux, Node runtime).
# The script packages the compiled assets with a lightweight Express server so the SPA can run
# behind Application Gateway or other reverse proxies.
#
# Expected directory layout:
#   frontend-typescript-vite/           → Vite SPA source
#   infrastructure/azure/scripts...     → current script lives here
#
# Environment variables (optional):
#   RESOURCE_GROUP          - Azure resource group (auto-detect or prompt if not provided)
#   APP_SERVICE_NAME        - Name of the web app (default: web-subnet-calc-private)
#   APP_SERVICE_PLAN_NAME   - App Service plan to use (must exist)
#   API_BASE_URL            - Base URL the SPA should call (defaults to https://apim.../api/subnet-calc)
#   STACK_NAME              - Display label shown in the UI (optional)
#   VITE_AUTH_ENABLED       - Pass-through to frontend build (optional)
#
# Usage:
#   ./59-deploy-typescript-app-service.sh
#   APP_SERVICE_NAME="web-subnet-calc" ./59-deploy-typescript-app-service.sh

set -euo pipefail

# Colours for logs
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FRONTEND_DIR="${PROJECT_ROOT}/frontend-typescript-vite"

# Ensure Azure CLI session
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login' first."
  exit 1
fi

# Resolve resource group
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  RG_COUNT=$(az group list --query "length(@)" -o tsv)
  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found. Set RESOURCE_GROUP or create one."
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found. Set RESOURCE_GROUP to continue."
    az group list --query "[].name" -o tsv >&2
    exit 1
  fi
fi

# Default configuration
readonly APP_SERVICE_NAME="${APP_SERVICE_NAME:-web-subnet-calc-private}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-plan-subnet-calc-web}"
readonly API_BASE_URL="${API_BASE_URL:-https://apim-subnet-calc-05845.azure-api.net/api/subnet-calc}"
readonly STACK_NAME="${STACK_NAME:-Subnet Calculator}"

log_info "Configuration:"
log_info "  Resource Group:        ${RESOURCE_GROUP}"
log_info "  App Service Plan:      ${APP_SERVICE_PLAN_NAME}"
log_info "  App Service Name:      ${APP_SERVICE_NAME}"
log_info "  API Base URL:          ${API_BASE_URL}"

# Verify frontend source
if [[ ! -d "${FRONTEND_DIR}" ]]; then
  log_error "Frontend directory not found: ${FRONTEND_DIR}"
  exit 1
fi

# Ensure App Service plan exists (do not create here – stack script should own lifecycle)
if ! az appservice plan show --name "${APP_SERVICE_PLAN_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "App Service plan '${APP_SERVICE_PLAN_NAME}' not found in ${RESOURCE_GROUP}."
  log_error "Create it first (e.g. ./12-create-app-service-plan.sh with PLAN_NAME=${APP_SERVICE_PLAN_NAME})."
  exit 1
fi

# Create app if missing
if ! az webapp show --name "${APP_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Creating App Service ${APP_SERVICE_NAME} on plan ${APP_SERVICE_PLAN_NAME} (Node 18 LTS)..."
  az webapp create \
    --name "${APP_SERVICE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --plan "${APP_SERVICE_PLAN_NAME}" \
    --runtime "NODE|18-lts" \
    --output none
else
  log_info "App Service ${APP_SERVICE_NAME} already exists – will update deployment."
fi

# Build the frontend
log_info "Installing dependencies and building TypeScript frontend..."
pushd "${FRONTEND_DIR}" >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci >/dev/null
else
  npm install >/dev/null
fi
npm run build >/dev/null
popd >/dev/null
log_info "Build complete (output: ${FRONTEND_DIR}/dist)"

# Prepare Express wrapper
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log_info "Preparing deployment package..."
mkdir -p "${WORK_DIR}/public"
cp -R "${FRONTEND_DIR}/dist/"* "${WORK_DIR}/public/"

cat > "${WORK_DIR}/package.json" <<'EOF'
{
  "name": "subnet-calc-typescript",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "compression": "^1.7.4",
    "express": "^4.19.2"
  }
}
EOF

cat > "${WORK_DIR}/server.js" <<'EOF'
const compression = require('compression');
const express = require('express');
const path = require('path');

const app = express();
const port = process.env.PORT || 8080;

app.use(compression());
app.use(express.static(path.join(__dirname, 'public'), {
  index: 'index.html',
  maxAge: '1h',
}));

// SPA fallback
app.get('*', (_, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, () => {
  console.log(`TypeScript frontend listening on port ${port}`);
});
EOF

# Install production dependencies locally so the package runs without build step on App Service
pushd "${WORK_DIR}" >/dev/null
npm install --production >/dev/null
popd >/dev/null

# Ensure API metadata is available to the SPA
cat > "${WORK_DIR}/.env" <<EOF
VITE_API_URL=${API_BASE_URL}
VITE_STACK_NAME=${STACK_NAME}
EOF

# Create deployment zip (include node_modules)
DEPLOY_ZIP="${WORK_DIR}/deploy.zip"
pushd "${WORK_DIR}" >/dev/null
zip -r "${DEPLOY_ZIP}" . >/dev/null
popd >/dev/null

log_info "Deploying to App Service (zip)..."
az webapp deploy \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --src-path "${DEPLOY_ZIP}" \
  --type zip \
  --async false \
  --restart true \
  --output none

# Configure app settings
log_info "Updating application settings..."
az webapp config appsettings set \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    API_BASE_URL="${API_BASE_URL}" \
    STACK_NAME="${STACK_NAME}" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=false \
    WEBSITE_NODE_DEFAULT_VERSION="~18" \
  --output none

# Ensure site listens via npm start
log_info "Setting startup command (npm start)..."
az webapp config set \
  --name "${APP_SERVICE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --startup-file "npm start" \
  --output none

log_info ""
log_info "==============================================="
log_info "TypeScript frontend deployed to App Service ✅"
log_info "  App Service:  ${APP_SERVICE_NAME}"
log_info "  Plan:         ${APP_SERVICE_PLAN_NAME}"
log_info "  Resource RG:  ${RESOURCE_GROUP}"
log_info "  API URL:      ${API_BASE_URL}"
log_info "==============================================="
log_info ""
log_info "Verify deployment:"
log_info "  az webapp log tail --name ${APP_SERVICE_NAME} --resource-group ${RESOURCE_GROUP}"
log_info "  open https://${APP_SERVICE_NAME}.azurewebsites.net"
