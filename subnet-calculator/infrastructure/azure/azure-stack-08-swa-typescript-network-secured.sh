#!/usr/bin/env bash
#
# stack-06-swa-typescript-network-secured.sh - Deploy Stack 06: Network-Secured Function
#
# Architecture:
#   User → Entra ID → SWA → Function App (IP restricted + header validation)
#   Defense-in-depth: Auth + IP restrictions + header validation
#
# Security layers:
#   1. Entra ID (user authentication)
#   2. IP restrictions (only Azure SWA service tag)
#   3. Header validation (must come from correct SWA domain)
#
# Cost: ~$9/month (same as Stack 05b, but much more secure)
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" \
#     ./stack-06-swa-typescript-network-secured.sh

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
readonly SUBDOMAIN="${SUBDOMAIN:-network-secured}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-network}"
readonly LOCATION="${LOCATION:-uksouth}"

echo ""
log_info "========================================="
log_info "Stack 06: Network-Secured Function App"
log_info "========================================="
log_info ""
log_info "Security layers:"
log_info "  1. Entra ID authentication"
log_info "  2. IP restrictions (Azure SWA service tag)"
log_info "  3. Header validation (correct SWA domain)"
log_info ""
log_info "Cost: ~\$9/month (Consumption plan)"
log_info "Better security than Stack 05b, same cost"
log_info ""

# Check required vars
[[ -z "${AZURE_CLIENT_ID:-}" ]] && { log_error "AZURE_CLIENT_ID required"; exit 1; }
[[ -z "${AZURE_CLIENT_SECRET:-}" ]] && { log_error "AZURE_CLIENT_SECRET required"; exit 1; }

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
log_step "Step 1/6: Creating Function App..."
export RESOURCE_GROUP LOCATION
"${SCRIPT_DIR}/10-function-app.sh"

FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" \
  --query "sort_by(@, &lastModifiedTimeUtc)[-1].name" -o tsv)

# Step 2: Configure IP restrictions
log_step "Step 2/6: Configuring IP restrictions..."

log_info "Adding IP restriction for Azure SWA service tag..."
az functionapp config access-restriction add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "Allow-Azure-SWA" \
  --action Allow \
  --service-tag AzureStaticWebApps \
  --priority 100 \
  --output none

log_info "Adding deny-all rule..."
az functionapp config access-restriction add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "Deny-All" \
  --action Deny \
  --ip-address "0.0.0.0/0" \
  --priority 200 \
  --output none

log_info "IP restrictions configured"

# Step 3: Create SWA with Entra ID (before function deployment)
log_step "Step 3/6: Creating SWA with Entra ID..."
export STATIC_WEB_APP_NAME STATIC_WEB_APP_SKU="Standard"
"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)

log_info "SWA created at: https://${SWA_URL}"

# Step 4: Deploy Function code with header validation
log_step "Step 4/6: Deploying Function code with header validation..."

log_info "Configuring header validation middleware..."
log_info "  - AUTH_METHOD: none (using IP restrictions + headers instead)"
log_info "  - ALLOWED_SWA_HOSTS: ${SWA_URL}"
log_info "  - CORS_ORIGINS: https://${SWA_URL}"
log_info ""
log_info "Defense-in-depth security:"
log_info "  1. IP restrictions validate traffic comes from Azure SWA service tag"
log_info "  2. Header validation ensures requests are from the correct SWA domain"
log_info "  3. Together they prevent unauthorized access even with valid Azure SWA IPs"
log_info ""

export FUNCTION_APP_NAME DISABLE_AUTH=true
"${SCRIPT_DIR}/22-deploy-function-zip.sh"

# Configure header validation environment variables
log_info "Setting header validation environment variables..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=none \
    ALLOWED_SWA_HOSTS="${SWA_URL}" \
    CORS_ORIGINS="https://${SWA_URL}" \
  --output none

log_info "Header validation configured"
sleep 30

# Step 5: Configure SWA Entra ID settings
log_step "Step 5/6: Configuring SWA Entra ID settings..."
az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

log_info "Entra ID settings configured"

# Step 6: Deploy frontend
log_step "Step 6/6: Deploying frontend..."
FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"

[[ ! -d "node_modules" ]] && npm install

FUNCTION_APP_URL="https://$(az functionapp show --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query "properties.defaultHostName" -o tsv)"

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
log_info "Stack 06 deployment complete!"
log_info "========================================="
log_info ""
log_info "Frontend: https://${SWA_URL}"
log_info "Backend:  ${FUNCTION_APP_URL}"
log_info ""
log_info "Security configuration:"
log_info "  ✓ Entra ID (SWA user authentication)"
log_info "  ✓ IP restrictions (Azure SWA service tag only)"
log_info "  ✓ Header validation (CORS + SWA host check)"
log_info ""
log_info "Function App environment variables:"
log_info "  - AUTH_METHOD=none"
log_info "  - ALLOWED_SWA_HOSTS=${SWA_URL}"
log_info "  - CORS_ORIGINS=https://${SWA_URL}"
log_info ""
log_info "Defense-in-depth layers:"
log_info "  1. IP restrictions: Only Azure SWA service tag can reach function"
log_info "  2. CORS validation: Browser enforces same-origin policy"
log_info "  3. Host validation: Function validates requests from correct SWA domain"
log_info ""
log_info "Note: Header validation applies to direct API calls only."
log_info "      When SWA is linked, it proxies requests without headers."
log_info "      IP restrictions provide the primary protection layer."
log_info ""
log_info "Test frontend:"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "Test direct access (will be blocked by IP restriction):"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info "  Expected: 403 Forbidden"
log_info ""
log_info "Cost: ~\$9/month with enterprise-grade security!"
log_info ""
log_info "========================================="
echo ""
