#!/usr/bin/env bash
#
# Create Azure Storage Account with static website hosting
# - Standard LRS (cheapest option: ~$0.05/month for static content)
# - Static website enabled
# - No custom domain initially (manual DNS configuration)
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

# Check for existing storage accounts for static websites
if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
  log_info "STORAGE_ACCOUNT_NAME not set. Checking for existing storage accounts..."

  # Storage account names must be globally unique and 3-24 lowercase alphanumeric
  # Generate default name if none provided
  RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
  STORAGE_ACCOUNT_NAME="stsubnetcalc${RANDOM_SUFFIX}"
fi

# Configuration
readonly STORAGE_ACCOUNT_NAME
readonly STORAGE_SKU="${STORAGE_SKU:-Standard_LRS}"
readonly INDEX_DOCUMENT="${INDEX_DOCUMENT:-index.html}"
readonly ERROR_404_DOCUMENT="${ERROR_404_DOCUMENT:-404.html}"

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
log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "  SKU: ${STORAGE_SKU}"
log_info "  Index Document: ${INDEX_DOCUMENT}"
log_info "  Error Document: ${ERROR_404_DOCUMENT}"

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

# Check if storage account already exists
if az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "Storage account ${STORAGE_ACCOUNT_NAME} already exists"

  # Check if static website is already enabled
  STATIC_WEBSITE_ENABLED=$(az storage blob service-properties show \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login \
    --query "staticWebsite.enabled" -o tsv 2>/dev/null || echo "false")

  if [[ "${STATIC_WEBSITE_ENABLED}" == "true" ]]; then
    log_info "Static website already enabled"
  else
    log_info "Enabling static website on existing storage account..."
    az storage blob service-properties update \
      --account-name "${STORAGE_ACCOUNT_NAME}" \
      --auth-mode login \
      --static-website \
      --index-document "${INDEX_DOCUMENT}" \
      --404-document "${ERROR_404_DOCUMENT}" \
      --output none
  fi
else
  # Create storage account
  log_info "Creating storage account ${STORAGE_ACCOUNT_NAME}..."
  az storage account create \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku "${STORAGE_SKU}" \
    --kind StorageV2 \
    --allow-blob-public-access true \
    --output none

  log_info "Storage account created successfully"

  # Enable static website hosting
  log_info "Enabling static website hosting..."
  az storage blob service-properties update \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login \
    --static-website \
    --index-document "${INDEX_DOCUMENT}" \
    --404-document "${ERROR_404_DOCUMENT}" \
    --output none

  log_info "Static website hosting enabled"
fi

# Get static website URL
STATIC_WEBSITE_URL=$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "primaryEndpoints.web" -o tsv)

# Get primary web endpoint (alternative format)
PRIMARY_WEB_ENDPOINT=$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "primaryEndpoints.web" -o tsv | sed 's|https://||' | sed 's|/$||')

log_info ""
log_info "========================================="
log_info "Storage Account created successfully!"
log_info "========================================="
log_info "Name: ${STORAGE_ACCOUNT_NAME}"
log_info "Static Website URL: ${STATIC_WEBSITE_URL}"
log_info "Primary Web Endpoint: ${PRIMARY_WEB_ENDPOINT}"
log_info ""
log_info "Container endpoint: \$web"
log_info "Index document: ${INDEX_DOCUMENT}"
log_info "Error document: ${ERROR_404_DOCUMENT}"
log_info ""
log_info "Cost estimate:"
log_info "  Storage (first 50GB): ~\$0.018/GB/month"
log_info "  Bandwidth (first 5GB): Free, then \$0.087/GB"
log_info "  Operations: ~\$0.004/10k operations"
log_info "  Typical monthly cost for static site: ~\$0.05-0.10"
log_info ""
log_info "DNS Configuration:"
log_info "  Add CNAME record pointing to: ${PRIMARY_WEB_ENDPOINT}"
log_info "  Example: static.yourdomain.com → ${PRIMARY_WEB_ENDPOINT}"
log_info ""
log_info "Next steps:"
log_info "  1. Deploy static content: ./25-deploy-static-website-storage.sh"
log_info "  2. Configure custom domain (optional):"
log_info "     az storage account update --name ${STORAGE_ACCOUNT_NAME} \\"
log_info "       --resource-group ${RESOURCE_GROUP} \\"
log_info "       --custom-domain static.yourdomain.com"
log_info ""
log_info "To upload files manually:"
log_info "  az storage blob upload-batch \\"
log_info "    --account-name ${STORAGE_ACCOUNT_NAME} \\"
log_info "    --auth-mode login \\"
log_info "    --source ./frontend-html-static \\"
log_info "    --destination '\$web' \\"
log_info "    --overwrite"
log_info ""
