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

# Source selection utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

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
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
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
readonly STATIC_WEB_APP_SKU="${STATIC_WEB_APP_SKU:-Standard}"

# SKU Options:
# - Free: Good for testing only
#   - 100 GB bandwidth/month
#   - 0.5 GB storage
#   - Azure domains only (*.azurestaticapps.net)
#   - No custom authentication
#   - Managed Functions (limited regions)
#
# - Standard: Recommended for production (DEFAULT)
#   - ~$9/month per app
#   - Custom domains with free SSL certificates (up to 5 per app)
#   - Custom authentication (Entra ID, etc.)
#   - 100 GB bandwidth/month
#   - 2 GB storage (4x more than Free)
#   - Managed or Bring Your Own Functions
#   - SLA available
#
# To use Free tier for testing: STATIC_WEB_APP_SKU=Free ./00-static-web-app.sh

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    RG_LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected resource group location: ${RG_LOCATION}"
    log_info ""
    log_info "NOTE: Azure Static Web Apps is a global service."
    log_info "  - Static assets are globally distributed (CDN)"
    log_info "  - Region selection ONLY affects managed Azure Functions location"
    log_info "  - If using 'Bring Your Own Functions', region doesn't matter"
    log_info ""

    # Static Web Apps managed functions are only available in specific regions
    # Available: westus2, centralus, eastus2, westeurope, eastasia
    # Default: westeurope (good for EU/UK deployments)
    # Map common regions to nearest Static Web App region
    case "${RG_LOCATION}" in
      westus|westus3)
        LOCATION="westus2"
        log_info "Resource group is in ${RG_LOCATION}"
        log_info "Using nearest SWA managed functions region: ${LOCATION}"
        ;;
      eastus|eastus3)
        LOCATION="eastus2"
        log_info "Resource group is in ${RG_LOCATION}"
        log_info "Using nearest SWA managed functions region: ${LOCATION}"
        ;;
      centralus|westus2|eastus2|eastasia)
        LOCATION="${RG_LOCATION}"
        log_info "Using resource group location for managed functions: ${LOCATION}"
        ;;
      westeurope|uksouth|ukwest|northeurope)
        LOCATION="westeurope"
        log_info "Resource group is in ${RG_LOCATION}"
        log_info "Using westeurope for SWA managed functions (recommended for EU/UK)"
        ;;
      *)
        # Default to westeurope for other regions
        LOCATION="westeurope"
        log_info "Resource group is in ${RG_LOCATION}"
        log_info "Using default SWA managed functions region: ${LOCATION}"
        log_info ""
        log_info "Available SWA managed functions regions:"
        log_info "  westus2, centralus, eastus2, westeurope, eastasia"
        log_info "Override with: LOCATION=eastus2 ./00-static-web-app.sh"
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
log_info "  Location: ${LOCATION} (for managed Functions only - static assets are global)"
log_info "  Static Web App Name: ${STATIC_WEB_APP_NAME}"
log_info "  SKU: ${STATIC_WEB_APP_SKU}"
if [[ "${STATIC_WEB_APP_SKU}" == "Free" ]]; then
  log_info ""
  log_warn "Using Free tier - suitable for testing only"
  log_warn "Limitations:"
  log_warn "  - Azure domains only (*.azurestaticapps.net)"
  log_warn "  - No custom authentication (Entra ID)"
  log_warn "  - No custom domains"
  log_warn "  - 0.5 GB storage (vs 2 GB on Standard)"
  log_warn ""
  log_info "For production, use Standard tier (~\$9/month):"
  log_info "  STATIC_WEB_APP_SKU=Standard ./00-static-web-app.sh"
elif [[ "${STATIC_WEB_APP_SKU}" == "Standard" ]]; then
  log_info ""
  log_info "Using Standard tier (~\$9/month per app) - recommended for production"
  log_info "Features enabled:"
  log_info "  ✓ Custom domains with free SSL (up to 5 per app)"
  log_info "  ✓ Custom authentication (Entra ID)"
  log_info "  ✓ 2 GB storage"
  log_info "  ✓ SLA available"
fi

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
log_info "Location: ${LOCATION} (managed Functions only - static assets globally distributed)"
log_info ""
if [[ "${STATIC_WEB_APP_SKU}" == "Standard" ]]; then
  log_info "Standard tier features:"
  log_info "  ✓ Custom domains (up to 5) with free SSL certificates"
  log_info "  ✓ Custom authentication (Entra ID, custom providers)"
  log_info "  ✓ 2 GB storage"
  log_info "  ✓ SLA available"
  log_info "  ✓ Cost: ~\$9/month per app"
  log_info ""
elif [[ "${STATIC_WEB_APP_SKU}" == "Free" ]]; then
  log_warn "Free tier limitations:"
  log_warn "  - Azure domains only (*.azurestaticapps.net)"
  log_warn "  - No custom authentication (Entra ID)"
  log_warn "  - No custom domains"
  log_warn "  - 0.5 GB storage"
  log_warn ""
  log_info "To upgrade to Standard tier (~\$9/month):"
  log_info "  1. Azure Portal: Static Web App → Settings → Hosting plan → Upgrade"
  log_info "  2. Or recreate with: STATIC_WEB_APP_SKU=Standard ./00-static-web-app.sh"
  log_info ""
fi
log_info "Deployment Token (save this securely):"
echo "${DEPLOYMENT_TOKEN}"
log_info ""
log_info "Next steps:"
log_info "1. Use 20-deploy-frontend.sh to deploy a frontend"
log_info "2. Or set up GitHub Actions with this deployment token"
if [[ "${STATIC_WEB_APP_SKU}" == "Standard" ]]; then
  log_info "3. Configure custom domain: az staticwebapp hostname set --name ${STATIC_WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --hostname your-domain.com"
fi
log_info ""
log_info "To get the deployment token again, run:"
log_info "  az staticwebapp secrets list --name ${STATIC_WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --query properties.apiKey -o tsv"
