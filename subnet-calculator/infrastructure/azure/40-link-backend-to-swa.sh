#!/usr/bin/env bash
#
# Link a BYO (Bring Your Own) Function App to an Azure Static Web App
#
# This script links an existing Function App as a backend to a Static Web App,
# enabling the SWA to proxy API requests to the Function App. This is Azure's
# recommended pattern for Static Web Apps with custom backends.
#
# Usage:
#   # Interactive mode (prompts for all values)
#   ./40-link-backend-to-swa.sh
#
#   # Specify all parameters
#   STATIC_WEB_APP_NAME="stapp-subnet-calc" \
#   FUNCTION_APP_NAME="func-subnet-calc-123456" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   REGION="uksouth" \
#   ./40-link-backend-to-swa.sh
#
# Parameters:
#   STATIC_WEB_APP_NAME - Name of the Static Web App
#   FUNCTION_APP_NAME   - Name of the Function App to link
#   RESOURCE_GROUP      - Resource group containing both resources
#   REGION              - Azure region for the backend link (e.g., uksouth, eastus)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Static Web App must exist
#   - Function App must exist
#   - User must have permissions to modify both resources
#
# Notes:
#   - This creates a managed link between SWA and Function App
#   - The Function App should be secured with IP restrictions after linking
#   - Use 45-configure-ip-restrictions.sh to lock down the Function App
#   - The region parameter affects routing performance (use same region as Function App)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Get script directory and source utilities
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
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Auto-detect or prompt for STATIC_WEB_APP_NAME
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_info "STATIC_WEB_APP_NAME not set. Looking for Static Web Apps..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in resource group ${RESOURCE_GROUP}"
    log_error "Create one first with the Azure Portal or az staticwebapp create"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_warn "Multiple Static Web Apps found:"
    STATIC_WEB_APP_NAME=$(select_static_web_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
  fi
fi

# Auto-detect or prompt for FUNCTION_APP_NAME
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  log_info "FUNCTION_APP_NAME not set. Looking for Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in resource group ${RESOURCE_GROUP}"
    log_error "Create one first with ./10-function-app.sh"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Function App: ${FUNCTION_APP_NAME}"
  else
    log_warn "Multiple Function Apps found:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

# Detect location from resource group if REGION not set
if [[ -z "${REGION:-}" ]]; then
  REGION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Detected region from resource group: ${REGION}"
fi

log_info ""
log_info "========================================="
log_info "Link Configuration"
log_info "========================================="
log_info "Resource Group: ${RESOURCE_GROUP}"
log_info "Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "Function App:   ${FUNCTION_APP_NAME}"
log_info "Region:         ${REGION}"
log_info ""

# Verify Static Web App exists
log_step "Verifying Static Web App exists..."
if ! az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Static Web App found"

# Verify Function App exists
log_step "Verifying Function App exists..."
if ! az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Function App found"

# Get Function App resource ID
FUNCTION_APP_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info "Function App Resource ID: ${FUNCTION_APP_ID}"

# Check if backend is already linked
log_step "Checking for existing backend links..."
EXISTING_BACKENDS=$(az staticwebapp backends list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${EXISTING_BACKENDS}" -gt 0 ]]; then
  log_warn "Static Web App already has ${EXISTING_BACKENDS} backend(s) linked:"
  az staticwebapp backends list \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].[backendResourceId,region]" -o tsv | \
    awk '{printf "  - %s (%s)\n", $1, $2}'

  echo ""
  read -r -p "Continue to link another backend? (y/N): " confirm
  confirm=${confirm:-n}
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled"
    exit 0
  fi
fi

# Link Function App to Static Web App
log_step "Linking Function App to Static Web App..."
if az staticwebapp backends link \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --backend-resource-id "${FUNCTION_APP_ID}" \
  --region "${REGION}" \
  --output none; then
  log_info "Backend linked successfully"
else
  log_error "Failed to link backend"
  log_error "This might be due to:"
  log_error "  - Insufficient permissions"
  log_error "  - Function App already linked to another SWA"
  log_error "  - Invalid region (must be a valid Azure region)"
  exit 1
fi

# Verify the link
log_step "Verifying backend link..."
LINKED_BACKENDS=$(az staticwebapp backends list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?backendResourceId=='${FUNCTION_APP_ID}']" -o tsv)

if [[ -n "${LINKED_BACKENDS}" ]]; then
  log_info "Backend link verified successfully"
else
  log_warn "Backend link created but verification failed"
  log_warn "This might be an Azure API timing issue - check manually"
fi

# Get Static Web App URL
SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

# Get Function App URL
FUNC_HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")

# Handle empty hostname (Flex Consumption)
if [[ -z "${FUNC_HOSTNAME}" ]]; then
  FUNC_HOSTNAME="${FUNCTION_APP_NAME}.azurewebsites.net"
fi

log_info ""
log_info "========================================="
log_info "Backend Linked Successfully!"
log_info "========================================="
log_info "Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  URL: https://${SWA_HOSTNAME}"
log_info ""
log_info "Function App:   ${FUNCTION_APP_NAME}"
log_info "  URL: https://${FUNC_HOSTNAME}"
log_info ""
log_info "Backend Region: ${REGION}"
log_info ""
log_info "Next Steps:"
log_info "1. Configure IP restrictions on Function App to allow only SWA traffic:"
log_info "   ./45-configure-ip-restrictions.sh"
log_info ""
log_info "2. Test the API through the Static Web App:"
log_info "   curl https://${SWA_HOSTNAME}/api/v1/health"
log_info ""
log_info "3. Update frontend to use SWA hostname instead of direct Function App URL"
log_info ""
log_info "To unlink the backend:"
log_info "  az staticwebapp backends unlink \\"
log_info "    --name ${STATIC_WEB_APP_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP}"
log_info ""
