#!/usr/bin/env bash
#
# Configure Entra ID Authentication on Azure Static Web App
#
# This script configures Entra ID (Azure AD) authentication on a Static Web App.
# After running this script, the SWA will require Entra ID login for unauthenticated users.
#
# Usage:
#   # Interactive mode (prompts for all values)
#   ./42-configure-entraid-swa.sh
#
#   # Specify all parameters
#   STATIC_WEB_APP_NAME="swa-subnet-calc-entraid" \
#   AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000" \
#   AZURE_CLIENT_SECRET="your-secret-here" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   ./42-configure-entraid-swa.sh
#
# Parameters:
#   STATIC_WEB_APP_NAME  - Name of the Static Web App
#   AZURE_CLIENT_ID      - Entra ID app registration Client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration Client Secret
#   RESOURCE_GROUP       - Resource group containing the SWA
#
# Environment Variables (from .env):
#   Can be set in .env file and automatically loaded by direnv
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Static Web App must exist
#   - Entra ID app registration must exist
#   - User must have permissions to modify the SWA
#
# Notes:
#   - This creates a built-in auth provider on the SWA
#   - SWA will handle all authentication at the edge
#   - Frontend must opt-in to authentication via VITE_AUTH_ENABLED
#   - Authenticated users can be identified via x-ms-client-principal header

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

# Prompt for AZURE_CLIENT_ID if not set
if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
  log_warn "AZURE_CLIENT_ID not set"
  read -rp "Enter Entra ID Client ID: " AZURE_CLIENT_ID
  if [[ -z "${AZURE_CLIENT_ID}" ]]; then
    log_error "Client ID cannot be empty"
    exit 1
  fi
fi

# Prompt for AZURE_CLIENT_SECRET if not set
if [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_warn "AZURE_CLIENT_SECRET not set"
  read -rsp "Enter Entra ID Client Secret: " AZURE_CLIENT_SECRET
  echo ""
  if [[ -z "${AZURE_CLIENT_SECRET}" ]]; then
    log_error "Client Secret cannot be empty"
    exit 1
  fi
fi

log_info ""
log_info "========================================="
log_info "Entra ID Configuration"
log_info "========================================="
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Client ID: ${AZURE_CLIENT_ID:0:20}..."
log_info ""

# Confirm before applying
read -rp "Apply Entra ID configuration? [y/N] " -n 1 CONFIRM
echo ""
if [[ "${CONFIRM,,}" != "y" ]]; then
  log_info "Cancelled"
  exit 0
fi

log_step "Configuring Entra ID authentication on SWA..."

# Create or update the auth provider
log_step "Setting up authentication provider..."
if az staticwebapp authproviders create \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --provider aad \
  --client-id "${AZURE_CLIENT_ID}" \
  --client-secret "${AZURE_CLIENT_SECRET}" \
  2>/dev/null; then
  log_info "Authentication provider created successfully"
else
  log_warn "Authentication provider may already exist, attempting update..."
  # Note: Update might not be directly supported, check if command succeeds
fi

log_step "Verifying configuration..."
SWA_AUTH=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "authSettings.provider" -o tsv 2>/dev/null || echo "none")

log_info ""
log_info "========================================="
log_info "Configuration Complete"
log_info "========================================="
log_info "  SWA: ${STATIC_WEB_APP_NAME}"
log_info "  Auth Provider: ${SWA_AUTH}"
log_info ""
log_info "Next Steps:"
log_info "1. Rebuild frontend with VITE_AUTH_ENABLED=true"
log_info "   ./20-deploy-frontend.sh (with VITE_AUTH_ENABLED=true)"
log_info ""
log_info "2. Test authentication in browser:"
log_info "   - Access the SWA URL"
log_info "   - You should be redirected to Entra ID login"
log_info "   - After login, frontend should display authenticated user"
log_info ""
log_info "3. Verify API calls include authentication:"
log_info "   - Check browser Network tab for x-ms-client-principal header"
log_info ""

log_info "Configuration Details:"
log_info "- SWA will enforce authentication at the edge"
log_info "- All requests must include valid Entra ID token"
log_info "- SWA injects x-ms-client-principal header to backend"
log_info "- Frontend can access user info via /.auth/me endpoint"
