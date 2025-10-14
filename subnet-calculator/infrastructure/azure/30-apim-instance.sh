#!/usr/bin/env bash
#
# Create Azure API Management (APIM) instance for subnet calculator
# - SKU: Developer (sandbox-compatible, no SLA, single deployment unit)
# - Provisioning time: ~37 minutes (tested in eastus)
# - Works in sandbox environments (pre-existing resource group)
#
# IMPORTANT: APIM provisioning takes approximately 37 minutes
# Plan accordingly when testing in Pluralsight sandbox (4-hour limit)

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

# Auto-detect or prompt for PUBLISHER_EMAIL
if [[ -z "${PUBLISHER_EMAIL:-}" ]]; then
  log_info "PUBLISHER_EMAIL not set. Detecting from Azure account..."
  PUBLISHER_EMAIL=$(az account show --query user.name -o tsv 2>/dev/null || echo "")

  if [[ -z "${PUBLISHER_EMAIL}" ]]; then
    log_warn "Could not auto-detect email from Azure account"
    read -r -p "Enter publisher email address: " PUBLISHER_EMAIL

    if [[ -z "${PUBLISHER_EMAIL}" ]]; then
      log_error "Publisher email is required for APIM"
      exit 1
    fi
  else
    log_info "Auto-detected email: ${PUBLISHER_EMAIL}"
  fi
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

# Check if APIM instance already exists in resource group before generating random name
if [[ -z "${APIM_NAME:-}" ]]; then
  log_info "APIM_NAME not set. Checking for existing APIM instances..."
  EXISTING_APIM_COUNT=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${EXISTING_APIM_COUNT}" -eq 1 ]]; then
    EXISTING_APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_APIM_SKU=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.name" -o tsv)
    EXISTING_APIM_STATE=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].provisioningState" -o tsv)

    log_info "Found existing APIM instance: ${EXISTING_APIM_NAME}"
    log_info "  SKU: ${EXISTING_APIM_SKU}"
    log_info "  State: ${EXISTING_APIM_STATE}"

    if [[ "${EXISTING_APIM_STATE}" == "Succeeded" ]]; then
      log_info ""
      log_warn "APIM instance already exists and is ready!"
      read -r -p "Use existing APIM instance? (Y/n): " use_existing
      use_existing=${use_existing:-y}

      if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
        APIM_NAME="${EXISTING_APIM_NAME}"
        APIM_SKU="${EXISTING_APIM_SKU}"

        # Get details and exit
        APIM_GATEWAY=$(az apim show \
          --name "${APIM_NAME}" \
          --resource-group "${RESOURCE_GROUP}" \
          --query gatewayUrl -o tsv)

        APIM_PORTAL=$(az apim show \
          --name "${APIM_NAME}" \
          --resource-group "${RESOURCE_GROUP}" \
          --query developerPortalUrl -o tsv 2>/dev/null || echo "Not available")

        log_info ""
        log_info "✓ Using existing APIM instance"
        log_info ""
        log_info "APIM Instance Details:"
        log_info "  Name: ${APIM_NAME}"
        log_info "  SKU: ${APIM_SKU}"
        log_info "  Gateway URL: ${APIM_GATEWAY}"
        log_info "  Developer Portal: ${APIM_PORTAL}"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Configure backend: ./31-apim-backend.sh"
        log_info "  2. Apply policies: ./32-apim-policies.sh"
        exit 0
      else
        log_info "Creating new APIM instance alongside existing one..."
      fi
    else
      log_warn "Existing APIM is still provisioning (State: ${EXISTING_APIM_STATE})"
      log_warn "Cannot create another APIM while one is provisioning"
      exit 1
    fi
  elif [[ "${EXISTING_APIM_COUNT}" -gt 1 ]]; then
    log_error "Multiple APIM instances already exist in ${RESOURCE_GROUP}:"
    az apim list --resource-group "${RESOURCE_GROUP}" --query "[].[name,sku.name,provisioningState]" -o tsv | \
      awk '{printf "  - %s (SKU: %s, State: %s)\n", $1, $2, $3}'
    log_error ""
    log_error "This is unusual and may indicate a problem."
    log_error "Use APIM_NAME environment variable to select which one to configure:"
    log_error ""
    log_error "  APIM_NAME=apim-subnet-calc-47022 ./31-apim-backend.sh"
    log_error "  APIM_NAME=apim-subnet-calc-47022 ./32-apim-policies.sh"
    log_error ""
    log_error "Or clean up unused instances first:"
    log_error "  az apim delete --name apim-subnet-calc-54349 --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi
fi

# Generate random name if still not set
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
readonly APIM_NAME="${APIM_NAME:-apim-subnet-calc-${RANDOM_SUFFIX}}"
readonly APIM_SKU="${APIM_SKU:-Developer}"
readonly PUBLISHER_NAME="${PUBLISHER_NAME:-Subnet Calculator}"

# Detect location from resource group
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected location from resource group: ${LOCATION}"
  else
    log_error "Resource group ${RESOURCE_GROUP} not found"
    log_error "Create it first with: az group create --name ${RESOURCE_GROUP} --location eastus"
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
log_warn "⏱️  This will take approximately 37 minutes"
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
