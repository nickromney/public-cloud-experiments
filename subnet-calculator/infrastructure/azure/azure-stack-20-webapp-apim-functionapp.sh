#!/usr/bin/env bash
#
# azure-stack-20-webapp-apim-functionapp.sh
#
# Reference deployment that fronts an internal-only Azure Function App with API Management (internal)
# and serves a Vite TypeScript SPA from Azure App Service through Application Gateway.
# Cloudflare/App Gateway provide public ingress, everything else stays on private networking.
#
# Components (default names):
#   - VNet + subnets (10.100.0.0/24)
#   - Function App (func-subnet-calc-private-endpoint) on plan-subnet-calc-private (P0V3 default)
#   - TypeScript SPA on web-subnet-calc-private (plan-subnet-calc-web, S1)
#   - API Management (apim-subnet-calc-05845) in internal mode
#   - Application Gateway (agw-swa-subnet-calc-private-endpoint)
#   - Private DNS zones: privatelink.azurewebsites.net, azure-api.net
#
# Steps:
#   1. Ensure VNet/subnets (11-create-vnet-infrastructure.sh)
#   2. Provision/reuse App Service Plan + Function App + deploy API + private endpoint
#   3. Import API into APIM under /api/subnet-calc and disable public Function access
#   4. Provision/reuse App Service Plan + Web App + deploy TypeScript SPA
#   5. Enable VNet integration, private endpoint, and lock down the web app
#   6. Update Application Gateway routing (/* → web app, /api/subnet-calc/* → APIM)
#   7. Configure private DNS so web app and APIM resolve privately
#
# Usage:
#   ./azure-stack-20-webapp-apim-functionapp.sh
#   LOCATION=westeurope FUNCTION_APP_PLAN_SKU=S1 ./azure-stack-20-webapp-apim-functionapp.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP, LOCATION, FUNCTION_APP_NAME, WEB_APP_NAME, APP_GATEWAY_NAME, APIM_NAME, etc.

set -euo pipefail

# Colourful logging
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/map-swa-region.sh"

# Defaults (override with env vars)
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly LOCATION="${LOCATION:-uksouth}"
readonly FUNCTION_APP_PLAN_NAME="${FUNCTION_APP_PLAN_NAME:-plan-subnet-calc-private}"
readonly FUNCTION_APP_PLAN_SKU="${FUNCTION_APP_PLAN_SKU:-P0V3}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-private-endpoint}"
readonly FUNCTION_STORAGE_TAG_NAME="purpose"
readonly FUNCTION_STORAGE_TAG_VALUE="func-subnet-calc-private-endpoint"
readonly FUNCTION_STORAGE_TAG="${FUNCTION_STORAGE_TAG_NAME}=${FUNCTION_STORAGE_TAG_VALUE}"
readonly FUNCTION_STORAGE_PREFIX="${FUNCTION_STORAGE_PREFIX:-stfuncprivateep}"
readonly WEB_APP_PLAN_NAME="${WEB_APP_PLAN_NAME:-plan-subnet-calc-web}"
readonly WEB_APP_PLAN_SKU="${WEB_APP_PLAN_SKU:-S1}"
readonly WEB_APP_NAME="${WEB_APP_NAME:-web-subnet-calc-private}"
readonly VNET_NAME="${VNET_NAME:-vnet-subnet-calc-private}"
readonly VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.100.0.0/24}"
readonly SUBNET_FUNCTION_NAME="${SUBNET_FUNCTION_NAME:-snet-function-integration}"
readonly SUBNET_FUNCTION_PREFIX="${SUBNET_FUNCTION_PREFIX:-10.100.0.0/28}"
readonly SUBNET_PE_NAME="${SUBNET_PE_NAME:-snet-private-endpoints}"
readonly SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.100.0.16/28}"
readonly SUBNET_WEB_INTEGRATION="${SUBNET_WEB_INTEGRATION:-snet-web-integration}"
readonly SUBNET_WEB_INTEGRATION_PREFIX="${SUBNET_WEB_INTEGRATION_PREFIX:-10.100.0.96/28}"
readonly APP_GATEWAY_NAME="${APP_GATEWAY_NAME:-agw-swa-subnet-calc-private-endpoint}"
readonly APIM_NAME="${APIM_NAME:-apim-subnet-calc-05845}"
readonly APIM_PRIVATE_IP="${APIM_PRIVATE_IP:-10.201.0.4}"
readonly API_BASE_PATH="${API_BASE_PATH:-api/subnet-calc}"
readonly API_BASE_URL="https://${APIM_NAME}.azure-api.net/${API_BASE_PATH}"
readonly PRIVATELINK_DNS_ZONE_WEB="privatelink.azurewebsites.net"
readonly APIM_PRIVATE_DNS_ZONE="azure-api.net"

# Ensure Azure CLI context
if ! az account show &>/dev/null; then
  log_error "Azure CLI not logged in. Run 'az login' first."
  exit 1
fi

log_info "========================================="
log_info "Stack 20: App Service + APIM + Function"
log_info "========================================="
log_info ""
log_info "Resource Group:      ${RESOURCE_GROUP}"
log_info "Region:              ${LOCATION}"
log_info "Function App:        ${FUNCTION_APP_NAME}"
log_info "Function Plan:       ${FUNCTION_APP_PLAN_NAME} (${FUNCTION_APP_PLAN_SKU})"
log_info "Web App:             ${WEB_APP_NAME}"
log_info "Web Plan:            ${WEB_APP_PLAN_NAME} (${WEB_APP_PLAN_SKU})"
log_info "Application Gateway: ${APP_GATEWAY_NAME}"
log_info "APIM:                ${APIM_NAME}"
log_info "API Path:            /${API_BASE_PATH}"
log_info ""

# Create resource group if missing
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_step "Creating resource group ${RESOURCE_GROUP} in ${LOCATION}..."
  az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none
fi

# -----------------------------------------------------------------------------
# VNet infrastructure
# -----------------------------------------------------------------------------
log_step "Ensuring VNet and subnets exist..."
export RESOURCE_GROUP LOCATION VNET_NAME VNET_ADDRESS_SPACE SUBNET_FUNCTION_NAME SUBNET_FUNCTION_PREFIX SUBNET_PE_NAME SUBNET_PE_PREFIX
"${SCRIPT_DIR}/11-create-vnet-infrastructure.sh"

# Ensure web integration subnet exists
if ! az network vnet subnet show --resource-group "${RESOURCE_GROUP}" --vnet-name "${VNET_NAME}" --name "${SUBNET_WEB_INTEGRATION}" &>/dev/null; then
  log_info "Creating subnet ${SUBNET_WEB_INTEGRATION} (${SUBNET_WEB_INTEGRATION_PREFIX}) for App Service VNet integration..."
  az network vnet subnet create \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_NAME}" \
    --name "${SUBNET_WEB_INTEGRATION}" \
    --address-prefixes "${SUBNET_WEB_INTEGRATION_PREFIX}" \
    --delegations Microsoft.Web/serverFarms \
    --output none
fi

# -----------------------------------------------------------------------------
# Function App + API
# -----------------------------------------------------------------------------
log_step "Provisioning App Service plan for Function App..."
export RESOURCE_GROUP PLAN_NAME="${FUNCTION_APP_PLAN_NAME}" PLAN_SKU="${FUNCTION_APP_PLAN_SKU}" LOCATION
"${SCRIPT_DIR}/12-create-app-service-plan.sh"

log_step "Ensuring Function App exists..."
# Attempt to reuse tagged storage account
STORAGE_ACCOUNT_NAME=$(az storage account list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?tags.${FUNCTION_STORAGE_TAG_NAME}=='${FUNCTION_STORAGE_TAG_VALUE}'].name | [0]" -o tsv)
if [[ -z "${STORAGE_ACCOUNT_NAME}" ]]; then
  STORAGE_ACCOUNT_NAME="${FUNCTION_STORAGE_PREFIX}$(openssl rand -hex 3)"
fi

export RESOURCE_GROUP FUNCTION_APP_NAME="${FUNCTION_APP_NAME}" APP_SERVICE_PLAN="${FUNCTION_APP_PLAN_NAME}" STORAGE_ACCOUNT_NAME STORAGE_ACCOUNT_TAG="${FUNCTION_STORAGE_TAG}" LOCATION
"${SCRIPT_DIR}/13-create-function-app-on-app-service-plan.sh"

log_step "Deploying Function App code..."
export RESOURCE_GROUP FUNCTION_APP_NAME="${FUNCTION_APP_NAME}" DISABLE_AUTH=true AUTO_APPROVE=1
"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_step "Configuring Function App VNet integration..."
export RESOURCE_GROUP FUNCTION_APP_NAME="${FUNCTION_APP_NAME}" VNET_NAME SUBNET_NAME="${SUBNET_FUNCTION_NAME}"
"${SCRIPT_DIR}/14-configure-function-vnet-integration.sh"

log_step "Importing API into API Management..."
export RESOURCE_GROUP APIM_NAME FUNCTION_APP_NAME="${FUNCTION_APP_NAME}" API_PATH="${API_BASE_PATH}"
"${SCRIPT_DIR}/31-apim-backend.sh"

log_step "Setting API properties (no subscription key)..."
az apim api update \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${API_BASE_PATH}" \
  --subscription-required false \
  --service-url "https://${FUNCTION_APP_NAME}.azurewebsites.net" \
  --output none

log_step "Creating private endpoint for Function App..."
if ! az network private-endpoint show --resource-group "${RESOURCE_GROUP}" --name "pe-${FUNCTION_APP_NAME}" &>/dev/null; then
  export RESOURCE_GROUP FUNCTION_APP_NAME="${FUNCTION_APP_NAME}" VNET_NAME SUBNET_NAME="${SUBNET_PE_NAME}" LOCATION
  "${SCRIPT_DIR}/46-create-private-endpoint.sh"
else
  log_info "Private endpoint pe-${FUNCTION_APP_NAME} already exists."
fi

log_step "Disabling public network access for Function App..."
az functionapp update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${FUNCTION_APP_NAME}" \
  --set publicNetworkAccess=Disabled \
  --output none

# -----------------------------------------------------------------------------
# Web App (TypeScript SPA)
# -----------------------------------------------------------------------------
log_step "Provisioning App Service plan for Web App..."
export RESOURCE_GROUP PLAN_NAME="${WEB_APP_PLAN_NAME}" PLAN_SKU="${WEB_APP_PLAN_SKU}" LOCATION
"${SCRIPT_DIR}/12-create-app-service-plan.sh"

log_step "Deploying TypeScript SPA to App Service..."
export RESOURCE_GROUP APP_SERVICE_PLAN_NAME="${WEB_APP_PLAN_NAME}" APP_SERVICE_NAME="${WEB_APP_NAME}" API_BASE_URL="${API_BASE_URL}"
"${SCRIPT_DIR}/59-deploy-typescript-app-service.sh"

log_step "Enabling VNet integration on Web App..."
az webapp vnet-integration add \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEB_APP_NAME}" \
  --vnet "${VNET_NAME}" \
  --subnet "${SUBNET_WEB_INTEGRATION}" \
  --output none

log_step "Creating private endpoint for Web App..."
WEB_APP_ID=$(az webapp show --name "${WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)
if ! az network private-endpoint show --resource-group "${RESOURCE_GROUP}" --name "pe-${WEB_APP_NAME}" &>/dev/null; then
  az network private-endpoint create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "pe-${WEB_APP_NAME}" \
    --location "${LOCATION}" \
    --vnet-name "${VNET_NAME}" \
    --subnet "${SUBNET_PE_NAME}" \
    --private-connection-resource-id "${WEB_APP_ID}" \
    --group-id sites \
    --connection-name "pe-${WEB_APP_NAME}-connection" \
    --output none
else
  log_info "Private endpoint pe-${WEB_APP_NAME} already exists."
fi

log_step "Linking private DNS zone (${PRIVATELINK_DNS_ZONE_WEB}) to Web App private endpoint..."
az network private-endpoint dns-zone-group create \
  --resource-group "${RESOURCE_GROUP}" \
  --endpoint-name "pe-${WEB_APP_NAME}" \
  --name "${WEB_APP_NAME}-dns" \
  --private-dns-zone "${PRIVATELINK_DNS_ZONE_WEB}" \
  --zone-name "${PRIVATELINK_DNS_ZONE_WEB}" \
  --output none || true

log_step "Locking down Web App public access..."
az webapp update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEB_APP_NAME}" \
  --set publicNetworkAccess=Disabled \
  --output none

# -----------------------------------------------------------------------------
# Application Gateway adjustments
# -----------------------------------------------------------------------------
log_step "Updating Application Gateway backend pool for SPA..."
WEB_PRIVATE_IP=$(az network private-endpoint show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "pe-${WEB_APP_NAME}" \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)
if [[ -z "${WEB_PRIVATE_IP}" ]]; then
  log_error "Unable to determine web app private IP."
  exit 1
fi

az network application-gateway address-pool update \
  --resource-group "${RESOURCE_GROUP}" \
  --gateway-name "${APP_GATEWAY_NAME}" \
  --name appGatewayBackendPool \
  --servers "${WEB_PRIVATE_IP}" \
  --output none

az network application-gateway http-settings update \
  --resource-group "${RESOURCE_GROUP}" \
  --gateway-name "${APP_GATEWAY_NAME}" \
  --name appGatewayBackendHttpSettings \
  --host-name "${WEB_APP_NAME}.azurewebsites.net" \
  --port 443 \
  --protocol Https \
  --output none

log_step "Routing /${API_BASE_PATH}/* to APIM..."
az network application-gateway url-path-map update \
  --resource-group "${RESOURCE_GROUP}" \
  --gateway-name "${APP_GATEWAY_NAME}" \
  --name path-map-swa-apim \
  --set "pathRules[1].paths=['/${API_BASE_PATH}/*']" \
  --output none

# -----------------------------------------------------------------------------
# Private DNS
# -----------------------------------------------------------------------------
log_step "Ensuring private DNS zone ${PRIVATELINK_DNS_ZONE_WEB} exists..."
if ! az network private-dns zone show --resource-group "${RESOURCE_GROUP}" --name "${PRIVATELINK_DNS_ZONE_WEB}" &>/dev/null; then
  az network private-dns zone create --resource-group "${RESOURCE_GROUP}" --name "${PRIVATELINK_DNS_ZONE_WEB}" --output none
fi

log_step "Ensuring private DNS zone ${APIM_PRIVATE_DNS_ZONE} exists..."
if ! az network private-dns zone show --resource-group "${RESOURCE_GROUP}" --name "${APIM_PRIVATE_DNS_ZONE}" &>/dev/null; then
  az network private-dns zone create --resource-group "${RESOURCE_GROUP}" --name "${APIM_PRIVATE_DNS_ZONE}" --output none
fi

log_step "Linking VNets to ${APIM_PRIVATE_DNS_ZONE}..."
for VNET in "${VNET_NAME}" "vnet-subnet-calc-apim-internal"; do
  if az network vnet show --resource-group "${RESOURCE_GROUP}" --name "${VNET}" &>/dev/null; then
    LINK_NAME="link-${VNET//_/}-apim"
    if ! az network private-dns link vnet show --resource-group "${RESOURCE_GROUP}" --zone-name "${APIM_PRIVATE_DNS_ZONE}" --name "${LINK_NAME}" &>/dev/null; then
      az network private-dns link vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${APIM_PRIVATE_DNS_ZONE}" \
        --name "${LINK_NAME}" \
        --virtual-network "${VNET}" \
        --registration-enabled false \
        --output none
    fi
  fi
done

log_step "Creating APIM private A record..."
az network private-dns record-set a create \
  --resource-group "${RESOURCE_GROUP}" \
  --zone-name "${APIM_PRIVATE_DNS_ZONE}" \
  --name "${APIM_NAME}" \
  --ttl 300 \
  --output none || true

az network private-dns record-set a add-record \
  --resource-group "${RESOURCE_GROUP}" \
  --zone-name "${APIM_PRIVATE_DNS_ZONE}" \
  --record-set-name "${APIM_NAME}" \
  --ipv4-address "${APIM_PRIVATE_IP}" \
  --output none

# -----------------------------------------------------------------------------
# Web App access restrictions
# -----------------------------------------------------------------------------
log_step "Updating Web App access restrictions..."
az webapp config access-restriction add \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${WEB_APP_NAME}" \
  --rule-name "AllowAppGateway" \
  --priority 200 \
  --action Allow \
  --subnet "$(az network vnet subnet show --resource-group "${RESOURCE_GROUP}" --vnet-name "${VNET_NAME}" --name "${SUBNET_PE_NAME}" --query id -o tsv)" \
  --ignore-missing-endpoint true \
  --output none || true

# -----------------------------------------------------------------------------
# Rollup
# -----------------------------------------------------------------------------
APPGW_IP=$(az network public-ip show \
  --ids "$(az network application-gateway show --resource-group "${RESOURCE_GROUP}" --name "${APP_GATEWAY_NAME}" --query 'frontendIPConfigurations[0].publicIPAddress.id' -o tsv)" \
  --query ipAddress -o tsv)

log_info ""
log_info "============================================================"
log_info "Stack 20 provisioning complete ✅"
log_info "============================================================"
log_info "Application Gateway Public IP: ${APPGW_IP}"
log_info "Web App private endpoint IP:   ${WEB_PRIVATE_IP}"
log_info "Function App private endpoint: $(az network private-endpoint show --resource-group "${RESOURCE_GROUP}" --name "pe-${FUNCTION_APP_NAME}" --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv 2>/dev/null)"
log_info "API Gateway URL:               ${API_BASE_URL}"
log_info ""
log_info "Next steps:"
log_info "  • Update DNS (Cloudflare) to point your hostname to ${APPGW_IP}"
log_info "  • Ensure the App Gateway listener certificate matches the hostname"
log_info "  • Verify end-to-end: curl https://<host> (frontend) and /api/subnet-calc/api/v1/health"
log_info ""
log_info "Scripts invoked:"
log_info "  11-create-vnet-infrastructure.sh"
log_info "  12-create-app-service-plan.sh"
log_info "  13-create-function-app-on-app-service-plan.sh"
log_info "  14-configure-function-vnet-integration.sh"
log_info "  22-deploy-function-zip.sh"
log_info "  31-apim-backend.sh"
log_info "  46-create-private-endpoint.sh"
log_info "  59-deploy-typescript-app-service.sh"
log_info ""
