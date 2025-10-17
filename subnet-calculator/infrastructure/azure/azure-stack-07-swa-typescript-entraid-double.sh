#!/usr/bin/env bash
#
# stack-05c-swa-typescript-entraid-double.sh - Deploy Stack 05c: Double Authentication
#
# Architecture:
#   User → Entra ID (SWA) → Entra ID (Function) → API
#   Both SWA and Function App have independent auth
#
# WARNING: Complex setup - tokens may not match
# Consider Stack 05b (linked) or Stack 06 (network secured) instead
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" TENANT_ID="xxx" \
#     ./stack-05c-swa-typescript-entraid-double.sh

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-entraid-double}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-double}"
readonly LOCATION="${LOCATION:-uksouth}"

echo ""
log_info "========================================="
log_info "Stack 05c: Double Authentication"
log_info "========================================="
log_info ""
log_warn "WARNING: Complex setup with potential token mismatch issues"
log_warn "Consider Stack 05b (linked) or Stack 06 (network secured) instead"
log_info ""

# Check required vars
[[ -z "${AZURE_CLIENT_ID:-}" ]] && { log_error "AZURE_CLIENT_ID required"; exit 1; }
[[ -z "${AZURE_CLIENT_SECRET:-}" ]] && { log_error "AZURE_CLIENT_SECRET required"; exit 1; }
[[ -z "${TENANT_ID:-}" ]] && { log_error "TENANT_ID required"; exit 1; }

az account show &>/dev/null || { log_error "Run 'az login'"; exit 1; }

read -r -p "Proceed? (Y/n): " confirm
[[ ! "${confirm:-y}" =~ ^[Yy]$ ]] && exit 0

# Auto-detect RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  RG_COUNT=$(az group list --query "length(@)" -o tsv)
  if [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
  else
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
  fi
fi

# Step 1: Create Function App
log_step "Step 1/5: Creating Function App..."
export RESOURCE_GROUP LOCATION
"${SCRIPT_DIR}/10-function-app.sh"

FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" \
  --query "sort_by(@, &lastModifiedTimeUtc)[-1].name" -o tsv)

log_info "Function App: ${FUNCTION_APP_NAME}"

# Step 2: Enable Entra ID on Function App
log_step "Step 2/5: Enabling Entra ID on Function App..."

az functionapp auth update \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --enabled true \
  --action LoginWithAzureActiveDirectory \
  --aad-client-id "${AZURE_CLIENT_ID}" \
  --aad-client-secret "${AZURE_CLIENT_SECRET}" \
  --aad-token-issuer-url "https://login.microsoftonline.com/${TENANT_ID}/v2.0" \
  --output none

log_info "Entra ID enabled on Function App"

# Step 3: Deploy Function code
log_step "Step 3/5: Deploying Function code..."
export FUNCTION_APP_NAME DISABLE_AUTH=false
"${SCRIPT_DIR}/22-deploy-function-zip.sh"
sleep 30

# Step 4: Create SWA with Entra ID
log_step "Step 4/5: Creating SWA with Entra ID..."
export STATIC_WEB_APP_NAME STATIC_WEB_APP_SKU="Standard"
"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)

az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

# Step 5: Deploy frontend
log_step "Step 5/5: Deploying frontend..."
FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"

[[ ! -d "node_modules" ]] && npm install

FUNCTION_APP_URL="https://$(az functionapp show --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query defaultHostName -o tsv)"

VITE_API_URL="${FUNCTION_APP_URL}" npm run build

[[ -f "staticwebapp-entraid.config.json" ]] && \
  cp staticwebapp-entraid.config.json dist/staticwebapp.config.json

DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

command -v swa &>/dev/null || npm install -g @azure/static-web-apps-cli

npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --api-location "" \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --env production

echo ""
log_info "========================================="
log_info "Stack 05c deployment complete!"
log_info "========================================="
log_info ""
log_info "Frontend: https://${SWA_URL}"
log_info "Backend:  ${FUNCTION_APP_URL}"
log_info ""
log_warn "Both resources have Entra ID authentication"
log_warn "Token exchange may be required for proper operation"
log_info ""
log_info "Test: open https://${SWA_URL}"
log_info ""
log_info "Direct API call will be blocked:"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info "  Expected: 401 Unauthorized"
log_info ""
log_info "========================================="
echo ""
