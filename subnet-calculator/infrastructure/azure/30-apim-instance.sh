#!/usr/bin/env bash
#
# Create Azure API Management (APIM) instance for subnet calculator
# - SKU: Developer (sandbox-compatible, no SLA, single deployment unit)
# - Provisioning time: ~45 minutes
# - Works in sandbox environments (pre-existing resource group)
#
# IMPORTANT: APIM provisioning takes approximately 45 minutes
# Plan accordingly when testing in Pluralsight sandbox (4-hour limit)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
readonly APIM_NAME="${APIM_NAME:-apim-subnet-calc-${RANDOM_SUFFIX}}"
readonly APIM_SKU="${APIM_SKU:-Developer}"
readonly PUBLISHER_EMAIL="${PUBLISHER_EMAIL:?PUBLISHER_EMAIL environment variable is required}"
readonly PUBLISHER_NAME="${PUBLISHER_NAME:-Subnet Calculator}"

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
log_info "  APIM Name: ${APIM_NAME}"
log_info "  SKU: ${APIM_SKU}"
log_info "  Publisher Email: ${PUBLISHER_EMAIL}"
log_info "  Publisher Name: ${PUBLISHER_NAME}"

# Validate SKU for sandbox compatibility
case "${APIM_SKU}" in
  Developer|Basic|Standard|Consumption)
    log_info "SKU ${APIM_SKU} is sandbox-compatible"
    ;;
  *)
    log_error "SKU ${APIM_SKU} not supported in Pluralsight sandbox"
    log_error "Allowed SKUs: Developer, Basic, Standard, Consumption"
    exit 1
    ;;
esac

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

# Check if APIM instance already exists
if az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "APIM instance ${APIM_NAME} already exists"

  # Get APIM details
  APIM_GATEWAY=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query gatewayUrl -o tsv)

  APIM_PORTAL=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query developerPortalUrl -o tsv 2>/dev/null || echo "Not available")

  log_info ""
  log_info "Existing APIM Instance Details:"
  log_info "  Gateway URL: ${APIM_GATEWAY}"
  log_info "  Developer Portal: ${APIM_PORTAL}"

  exit 0
fi

# Create APIM instance
log_warn "Creating APIM instance ${APIM_NAME}..."
log_warn "⏱️  This will take approximately 45 minutes"
log_warn "⏱️  Pluralsight sandbox has 4-hour limit - plan accordingly"

START_TIME=$(date +%s)

az apim create \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --publisher-email "${PUBLISHER_EMAIL}" \
  --publisher-name "${PUBLISHER_NAME}" \
  --sku-name "${APIM_SKU}" \
  --no-wait \
  --output none

log_info "APIM creation initiated (running in background)"
log_info "Waiting for provisioning to complete..."

# Poll for completion
ELAPSED=0
while true; do
  PROVISIONING_STATE=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

  ELAPSED=$(($(date +%s) - START_TIME))
  MINUTES=$((ELAPSED / 60))

  case "${PROVISIONING_STATE}" in
    Succeeded)
      log_info "✓ APIM instance created successfully (took ${MINUTES} minutes)"
      break
      ;;
    Failed)
      log_error "APIM creation failed"
      exit 1
      ;;
    NotFound)
      log_info "Waiting for APIM creation to start... (${MINUTES}m elapsed)"
      ;;
    *)
      log_info "Provisioning state: ${PROVISIONING_STATE} (${MINUTES}m elapsed)"
      ;;
  esac

  sleep 30
done

# Get APIM details
APIM_GATEWAY=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query gatewayUrl -o tsv)

APIM_PORTAL=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query developerPortalUrl -o tsv 2>/dev/null || echo "Not available")

log_info ""
log_info "✓ APIM Instance Created Successfully!"
log_info ""
log_info "APIM Details:"
log_info "  Name: ${APIM_NAME}"
log_info "  Gateway URL: ${APIM_GATEWAY}"
log_info "  Developer Portal: ${APIM_PORTAL}"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure backend: ./31-apim-backend.sh"
log_info "  2. Apply policies: ./32-apim-policies.sh"
log_info "  3. Deploy function: ./23-deploy-function-apim.sh"
log_info "  4. Deploy frontend: ./20-deploy-frontend.sh with USE_APIM=true"
log_info ""
log_info "Save this APIM name for other scripts: ${APIM_NAME}"
