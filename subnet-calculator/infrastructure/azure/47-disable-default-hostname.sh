#!/usr/bin/env bash
#
# 47-disable-default-hostname.sh - Disable Default *.azurestaticapps.net Hostname
#
# This script disables the default *.azurestaticapps.net hostname on an Azure Static Web App,
# making the custom domain the only accessible endpoint.
#
# Use case:
#   - High-security environments requiring single domain access
#   - Compliance requirements (e.g., ONLY custom domain in Entra ID redirect URIs)
#   - Prevent accidental access via default hostname
#
# Requirements:
#   - Azure CLI logged in
#   - Static Web App must have at least one custom domain configured
#   - User must have permissions to modify the Static Web App
#
# Usage:
#   STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   ./47-disable-default-hostname.sh
#
# Environment variables:
#   STATIC_WEB_APP_NAME  - Name of the Static Web App (required if multiple exist)
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#
# Note:
#   This uses the Azure REST API directly as the Azure CLI does not yet support
#   disabling the default hostname. The operation is idempotent.
#
# References:
#   https://learn.microsoft.com/en-us/azure/static-web-apps/custom-domain
#   https://learn.microsoft.com/en-us/rest/api/appservice/static-sites

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Banner
echo ""
log_info "========================================="
log_info "Disable Default azurestaticapps.net Hostname"
log_info "========================================="
echo ""

# Check prerequisites
command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }
command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
az account show &>/dev/null || { log_error "Not logged in to Azure"; exit 1; }

# Auto-detect or prompt for resource group
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  source "${SCRIPT_DIR}/lib/selection-utils.sh"
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found. Please select one:"
    RESOURCE_GROUP=$(select_resource_group)
  fi
fi

readonly RESOURCE_GROUP
log_info "Using resource group: ${RESOURCE_GROUP}"
echo ""

# Auto-detect or prompt for Static Web App
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  SWA_COUNT=$(az staticwebapp list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "length(@)" -o tsv)

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in resource group ${RESOURCE_GROUP}"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
    log_info "Auto-detected single Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_warn "Multiple Static Web Apps found:"
    az staticwebapp list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[].{Name:name, DefaultHost:defaultHostname, Location:location}" \
      --output table
    echo ""
    read -r -p "Enter Static Web App name: " STATIC_WEB_APP_NAME
  fi
fi

readonly STATIC_WEB_APP_NAME
log_info "Using Static Web App: ${STATIC_WEB_APP_NAME}"
echo ""

# Get SWA details
log_step "Checking Static Web App configuration..."
SWA_ID=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

DEFAULT_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App ID: ${SWA_ID}"
log_info "Default hostname: ${DEFAULT_HOSTNAME}"
echo ""

# Check for custom domains
CUSTOM_DOMAINS=$(az staticwebapp hostname list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].name" -o tsv)

CUSTOM_DOMAIN_COUNT=$(echo "${CUSTOM_DOMAINS}" | wc -l | tr -d ' ')

if [[ "${CUSTOM_DOMAIN_COUNT}" -eq 0 ]] || [[ -z "${CUSTOM_DOMAINS}" ]]; then
  log_error "No custom domains configured on this Static Web App"
  log_error "At least one custom domain is required before disabling the default hostname"
  log_error ""
  log_error "Configure a custom domain first using:"
  log_error "  ./41-configure-custom-domain-swa.sh"
  exit 1
fi

log_info "Custom domains configured:"
echo "${CUSTOM_DOMAINS}" | while read -r domain; do
  log_info "  - ${domain}"
done
echo ""

# Confirm action
log_warn "========================================="
log_warn "WARNING: This will disable the default hostname"
log_warn "========================================="
log_warn ""
log_warn "After this operation:"
log_warn "  ✗ https://${DEFAULT_HOSTNAME} will no longer be accessible"
log_warn "  ✓ Custom domain(s) will remain active"
log_warn "  ✓ This change is reversible (can be re-enabled later)"
log_warn ""
read -r -p "Continue? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  log_info "Operation cancelled"
  exit 0
fi

echo ""
log_step "Disabling default hostname..."
echo ""

# Get access token for REST API
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Construct REST API endpoint
API_VERSION="2022-03-01"
API_ENDPOINT="https://management.azure.com${SWA_ID}?api-version=${API_VERSION}"

# Get current SWA configuration
log_info "Fetching current configuration..."
CURRENT_CONFIG=$(curl -s -X GET \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API_ENDPOINT}")

# Check if default hostname is already disabled
CURRENT_STATE=$(echo "${CURRENT_CONFIG}" | jq -r '.properties.publicNetworkAccess // "Enabled"')

if [[ "${CURRENT_STATE}" == "Disabled" ]]; then
  log_info "Default hostname is already disabled"
  log_info "No action needed"
  exit 0
fi

# Create PATCH payload to disable default hostname
PATCH_PAYLOAD=$(cat <<EOF
{
  "properties": {
    "publicNetworkAccess": "Disabled"
  }
}
EOF
)

log_info "Disabling default hostname via REST API..."
RESPONSE=$(curl -s -X PATCH \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PATCH_PAYLOAD}" \
  "${API_ENDPOINT}")

# Check response for errors
ERROR_MESSAGE=$(echo "${RESPONSE}" | jq -r '.error.message // empty')

if [[ -n "${ERROR_MESSAGE}" ]]; then
  log_error "Failed to disable default hostname"
  log_error "Error: ${ERROR_MESSAGE}"
  exit 1
fi

# Verify the change
sleep 5
NEW_STATE=$(curl -s -X GET \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API_ENDPOINT}" | jq -r '.properties.publicNetworkAccess // "Enabled"')

if [[ "${NEW_STATE}" == "Disabled" ]]; then
  log_info "✓ Default hostname successfully disabled"
else
  log_warn "Warning: Could not verify hostname state change"
  log_warn "Current state: ${NEW_STATE}"
fi

echo ""
log_info "========================================="
log_info "Operation Complete"
log_info "========================================="
log_info ""
log_info "Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "Default hostname: ${DEFAULT_HOSTNAME} (DISABLED)"
log_info ""
log_info "Active custom domains:"
echo "${CUSTOM_DOMAINS}" | while read -r domain; do
  log_info "  ✓ https://${domain}"
done
echo ""
log_info "The Static Web App is now accessible ONLY via custom domain(s)"
log_info ""
log_warn "To re-enable the default hostname, use Azure Portal or set:"
log_warn '  "publicNetworkAccess": "Enabled"'
log_warn "  via the same REST API endpoint"
log_info ""
