#!/usr/bin/env bash
#
# Create Azure Static Web App for subnet calculator
# - SKU: Free (standard available via STATIC_WEB_APP_SKU env var)
# - No custom domain initially
# - No authentication initially (public access)
# - Works in sandbox environments (pre-existing resource group)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc}"
readonly STATIC_WEB_APP_SKU="${STATIC_WEB_APP_SKU:-Free}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory (reserved for future use)
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Check if Static Web Apps extension is installed
if ! az staticwebapp --help &>/dev/null; then
  log_warn "Azure CLI Static Web Apps extension not found. Installing..."
  az extension add --name staticwebapp --yes
fi

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
log_info "  Static Web App Name: ${STATIC_WEB_APP_NAME}"
log_info "  SKU: ${STATIC_WEB_APP_SKU}"

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

# Check if Static Web App already exists
if az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "Static Web App ${STATIC_WEB_APP_NAME} already exists"

  # Get deployment token
  DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query properties.apiKey -o tsv)

  # Get hostname
  HOSTNAME=$(az staticwebapp show \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query defaultHostname -o tsv)

  log_info "Existing Static Web App details:"
  log_info "  URL: https://${HOSTNAME}"
  log_info "  Deployment token retrieved (use for GitHub Actions or manual deployment)"

  exit 0
fi

# Create Static Web App
log_info "Creating Static Web App ${STATIC_WEB_APP_NAME}..."
az staticwebapp create \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku "${STATIC_WEB_APP_SKU}" \
  --output none

log_info "Static Web App created successfully"

# Get deployment token
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Get hostname
HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info ""
log_info "========================================="
log_info "Static Web App created successfully!"
log_info "========================================="
log_info "Name: ${STATIC_WEB_APP_NAME}"
log_info "URL: https://${HOSTNAME}"
log_info "SKU: ${STATIC_WEB_APP_SKU}"
log_info ""
log_info "Deployment Token (save this securely):"
echo "${DEPLOYMENT_TOKEN}"
log_info ""
log_info "Next steps:"
log_info "1. Use 03-deploy-frontend.sh to deploy a frontend"
log_info "2. Or set up GitHub Actions with this deployment token"
log_info ""
log_info "To get the deployment token again, run:"
log_info "  az staticwebapp secrets list --name ${STATIC_WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --query properties.apiKey -o tsv"
