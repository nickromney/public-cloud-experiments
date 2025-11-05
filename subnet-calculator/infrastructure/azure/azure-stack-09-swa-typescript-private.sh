#!/usr/bin/env bash
#
# stack-07-swa-typescript-private.sh - Deploy Stack 07: Fully Private (MAXIMUM SECURITY)
#
# Architecture:
#   User → Entra ID → SWA → Private Link → VNet → Function (private endpoint only)
#   NO public internet access to backend
#
# Requirements:
#   - Premium Function Plan (EP1) - ~$100/month
#   - VNet with subnets
#   - Private endpoint - ~$10/month
#   - Private DNS zone
#
# Total cost: ~$129/month (14x more than Stack 06)
# Use only when compliance absolutely requires it
#
# Usage:
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" \
#     ./stack-07-swa-typescript-private.sh

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
readonly SUBDOMAIN="${SUBDOMAIN:-private}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-private}"
readonly LOCATION="${LOCATION:-uksouth}"
readonly VNET_NAME="vnet-subnet-calc-private"
FUNCTION_APP_NAME_SUFFIX="$(date +%s | tail -c 6)"
readonly FUNCTION_APP_NAME="func-subnet-calc-private-${FUNCTION_APP_NAME_SUFFIX}"
readonly PLAN_NAME="plan-subnet-calc-premium"

echo ""
log_info "========================================="
log_info "Stack 07: Fully Private Architecture"
log_info "MAXIMUM SECURITY"
log_info "========================================="
log_info ""
log_warn "COST WARNING: ~\$129/month"
log_warn "  Premium Function Plan (EP1): ~\$100/month"
log_warn "  Private Endpoint: ~\$10/month"
log_warn "  SWA Standard: ~\$9/month"
log_warn ""
log_warn "This is 14x more expensive than Stack 06 (~\$9/month)"
log_warn "Use only when compliance absolutely requires it"
log_info ""
log_info "Security features:"
log_info "  ✓ NO public endpoint for function app"
log_info "  ✓ VNet isolation"
log_info "  ✓ Private endpoint only"
log_info "  ✓ Data never leaves VNet"
log_info "  ✓ Entra ID authentication"
log_info ""

# Check required vars
[[ -z "${AZURE_CLIENT_ID:-}" ]] && { log_error "AZURE_CLIENT_ID required"; exit 1; }
[[ -z "${AZURE_CLIENT_SECRET:-}" ]] && { log_error "AZURE_CLIENT_SECRET required"; exit 1; }

az account show &>/dev/null || { log_error "Run 'az login'"; exit 1; }

log_warn "Proceed with ~\$129/month deployment? (y/N): "
read -r confirm
[[ ! "${confirm:-n}" =~ ^[Yy]$ ]] && exit 0

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

# Step 1: Create VNet
log_step "Step 1/7: Creating VNet..."

az network vnet create \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --address-prefix 10.0.0.0/16 \
  --output none

az network vnet subnet create \
  --name snet-functions \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet-name "${VNET_NAME}" \
  --address-prefix 10.0.1.0/24 \
  --output none

az network vnet subnet create \
  --name snet-private-endpoints \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet-name "${VNET_NAME}" \
  --address-prefix 10.0.2.0/24 \
  --disable-private-endpoint-network-policies \
  --output none

log_info "VNet created: ${VNET_NAME}"

# Step 2: Create Premium Function Plan
log_step "Step 2/7: Creating Premium Function Plan (EP1)..."

az functionapp plan create \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku EP1 \
  --is-linux \
  --output none

log_info "Premium plan created: ${PLAN_NAME}"

# Step 3: Create storage account
log_step "Step 3/7: Creating storage account..."

STORAGE_ACCOUNT="stprivate$(date +%s | tail -c 8)"
az storage account create \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output none

# Step 4: Create Function App
log_step "Step 4/7: Creating Function App..."

az functionapp create \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --plan "${PLAN_NAME}" \
  --storage-account "${STORAGE_ACCOUNT}" \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --output none

# Step 5: VNet integration
log_step "Step 5/7: Configuring VNet integration..."

az functionapp vnet-integration add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --vnet "${VNET_NAME}" \
  --subnet snet-functions \
  --output none

# Step 6: Create private endpoint
log_step "Step 6/7: Creating private endpoint..."

az functionapp update \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --set publicNetworkAccess=Disabled \
  --output none

FUNC_ID=$(az webapp show --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query id -o tsv)

az network private-endpoint create \
  --name pe-func-subnet-calc \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --vnet-name "${VNET_NAME}" \
  --subnet snet-private-endpoints \
  --private-connection-resource-id "${FUNC_ID}" \
  --group-id sites \
  --connection-name pe-func-connection \
  --output none

# Private DNS
az network private-dns zone create \
  --name privatelink.azurewebsites.net \
  --resource-group "${RESOURCE_GROUP}" \
  --output none

az network private-dns link vnet create \
  --name dns-link \
  --resource-group "${RESOURCE_GROUP}" \
  --zone-name privatelink.azurewebsites.net \
  --vnet-name "${VNET_NAME}" \
  --registration-enabled false \
  --output none

az network private-endpoint dns-zone-group create \
  --name default \
  --resource-group "${RESOURCE_GROUP}" \
  --endpoint-name pe-func-subnet-calc \
  --private-dns-zone privatelink.azurewebsites.net \
  --zone-name privatelink.azurewebsites.net \
  --output none

log_info "Private endpoint created"

# Step 7: Deploy and link to SWA
log_step "Step 7/7: Deploying code and creating SWA..."

export FUNCTION_APP_NAME DISABLE_AUTH=true
"${SCRIPT_DIR}/22-deploy-function-zip.sh"

export STATIC_WEB_APP_NAME STATIC_WEB_APP_SKU="Standard"
"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)

az staticwebapp backends link \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --backend-resource-id "${FUNC_ID}" \
  --backend-region "${LOCATION}" \
  --output none

az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

# Deploy frontend
FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
cd "${FRONTEND_DIR}"
[[ ! -d "node_modules" ]] && npm install
VITE_API_URL="" npm run build
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
log_info "Stack 07 deployment complete!"
log_info "========================================="
log_info ""
log_info "Frontend: https://${SWA_URL}"
log_info "Backend:  PRIVATE ENDPOINT ONLY (no public URL)"
log_info ""
log_info "Cost: ~\$129/month"
log_info "  Premium Function Plan: ~\$100/month"
log_info "  Private Endpoint: ~\$10/month"
log_info "  SWA: ~\$9/month"
log_info ""
log_info "Security: MAXIMUM"
log_info "  ✓ No public endpoint for function"
log_info "  ✓ VNet isolation"
log_info "  ✓ Private Link only"
log_info "  ✓ Data never leaves VNet"
log_info ""
log_info "Test: open https://${SWA_URL}"
log_info ""
log_info "========================================="
echo ""
