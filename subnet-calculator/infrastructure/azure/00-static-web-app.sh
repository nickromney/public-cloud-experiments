#!/usr/bin/env bash
#
# Create Azure Static Web App for subnet calculator
# - SKU: Free (standard available via STATIC_WEB_APP_SKU env var)
# - No custom domain initially
# - No authentication initially (public access)
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

# Check if Static Web Apps extension is installed
if ! az staticwebapp --help &>/dev/null; then
  log_warn "Azure CLI Static Web Apps extension not found. Installing..."
  az extension add --name staticwebapp --yes
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

# Check for existing Static Web Apps before using default name
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_info "STATIC_WEB_APP_NAME not set. Checking for existing Static Web Apps..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 1 ]]; then
    EXISTING_SWA_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_SWA_URL=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].defaultHostname" -o tsv)

    log_info "Found existing Static Web App: ${EXISTING_SWA_NAME}"
    log_info "  URL: https://${EXISTING_SWA_URL}"
    log_warn "Static Web App already exists and is ready!"
    read -r -p "Use existing Static Web App? (Y/n): " use_existing
    use_existing=${use_existing:-y}

    if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
      STATIC_WEB_APP_NAME="${EXISTING_SWA_NAME}"

      # Get deployment token
      DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.apiKey -o tsv)

      log_info ""
      log_info "✓ Using existing Static Web App"
      log_info ""
      log_info "Static Web App Details:"
      log_info "  Name: ${STATIC_WEB_APP_NAME}"
      log_info "  URL: https://${EXISTING_SWA_URL}"
      log_info "  Deployment token retrieved"
      log_info ""
      log_info "Next steps:"
      log_info "  1. Deploy frontend: ./20-deploy-frontend.sh"
      exit 0
    fi
  elif [[ "${SWA_COUNT}" -gt 1 ]]; then
    log_error "Multiple Static Web Apps already exist in ${RESOURCE_GROUP}:"
    az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[].[name,defaultHostname]" -o tsv | \
      awk '{printf "  - %s (https://%s)\n", $1, $2}'
    log_error ""
    log_error "This is unusual for a single application."
    log_error "Use STATIC_WEB_APP_NAME environment variable to specify which one:"
    log_error ""
    log_error "  STATIC_WEB_APP_NAME=swa-subnet-calc ./20-deploy-frontend.sh"
    log_error ""
    log_error "Or clean up unused instances first:"
    log_error "  az staticwebapp delete --name swa-old-name --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi
fi

# Configuration
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc}"
readonly STATIC_WEB_APP_SKU="${STATIC_WEB_APP_SKU:-Free}"

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    RG_LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected resource group location: ${RG_LOCATION}"

    # Static Web Apps are only available in specific regions
    # Available: westus2, centralus, eastus2, westeurope, eastasia
    # Map common regions to nearest Static Web App region
    case "${RG_LOCATION}" in
      westus|westus3)
        LOCATION="westus2"
        log_warn "Resource group is in ${RG_LOCATION}, but Static Web Apps not available there"
        log_info "Using nearest supported region: ${LOCATION}"
        ;;
      eastus|eastus3)
        LOCATION="eastus2"
        log_warn "Resource group is in ${RG_LOCATION}, but Static Web Apps not available there"
        log_info "Using nearest supported region: ${LOCATION}"
        ;;
      centralus|westus2|eastus2|westeurope|eastasia)
        LOCATION="${RG_LOCATION}"
        log_info "Using resource group location: ${LOCATION} (Static Web Apps supported)"
        ;;
      *)
        # Default to centralus for other regions
        LOCATION="centralus"
        log_warn "Resource group is in ${RG_LOCATION}, but Static Web Apps not available there"
        log_info "Using default region: ${LOCATION}"
        log_info ""
        log_info "Available Static Web App regions: westus2, centralus, eastus2, westeurope, eastasia"
        log_info "Override with: LOCATION=westus2 ./00-static-web-app.sh"
        ;;
    esac
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
log_info "1. Use 20-deploy-frontend.sh to deploy a frontend"
log_info "2. Or set up GitHub Actions with this deployment token"
log_info ""
log_info "To get the deployment token again, run:"
log_info "  az staticwebapp secrets list --name ${STATIC_WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --query properties.apiKey -o tsv"
