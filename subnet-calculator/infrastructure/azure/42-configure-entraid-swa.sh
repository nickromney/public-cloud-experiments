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
GENERATED_DIR="${SCRIPT_DIR}/generated"

mkdir -p "${GENERATED_DIR}"

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
    # Try non-interactive selection (list names and pick first)
    RG_OPTIONS=$(az group list --query "[].name" -o tsv)
    if [[ -t 0 ]]; then
      # Terminal available - use interactive selection
      RESOURCE_GROUP=$(select_resource_group) || exit 1
    else
      # Non-interactive - pick first one
      RESOURCE_GROUP=$(echo "${RG_OPTIONS}" | head -1)
      log_warn "Non-interactive mode: selected first RG: ${RESOURCE_GROUP}"
    fi
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
    # Try non-interactive selection (list names and pick first)
    SWA_OPTIONS=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv)
    if [[ -t 0 ]]; then
      # Terminal available - use interactive selection
      STATIC_WEB_APP_NAME=$(select_static_web_app "${RESOURCE_GROUP}") || exit 1
    else
      # Non-interactive - pick first one
      STATIC_WEB_APP_NAME=$(echo "${SWA_OPTIONS}" | head -1)
      log_warn "Non-interactive mode: selected first SWA: ${STATIC_WEB_APP_NAME}"
    fi
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
  fi
fi

SWA_INFO=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" -o json)

SWA_HOSTNAME=$(echo "${SWA_INFO}" | jq -r '.defaultHostname')
LINKED_BACKEND_ID=$(echo "${SWA_INFO}" | jq -r '.linkedBackends[0].backendResourceId // empty')

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

# Detect tenant ID if not set
if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
  log_info "Detecting Entra ID tenant..."
  AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
fi

log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Tenant ID: ${AZURE_TENANT_ID}"
log_info "  Client ID: ${AZURE_CLIENT_ID:0:20}..."
log_info ""

# Confirm before applying (default to Y)
read -rp "Apply Entra ID configuration? [Y/n] " -n 1 CONFIRM
echo ""
CONFIRM="${CONFIRM:-y}"
if [[ "${CONFIRM,,}" != "y" ]]; then
  log_info "Cancelled"
  exit 0
fi

log_step "Configuring Entra ID authentication on SWA..."

# Set app settings for Entra ID credentials
log_step "Setting Entra ID credentials in SWA app settings..."
# Note: Using printf for proper variable expansion to avoid shell interpretation of special chars
CLIENT_ID_SETTING="AZURE_CLIENT_ID=$(printf "%s" "$AZURE_CLIENT_ID")"
CLIENT_SECRET_SETTING="AZURE_CLIENT_SECRET=$(printf "%s" "$AZURE_CLIENT_SECRET")"
TENANT_ID_SETTING="AZURE_TENANT_ID=$(printf "%s" "$AZURE_TENANT_ID")"

if az staticwebapp appsettings set --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --setting-names "$CLIENT_ID_SETTING" "$CLIENT_SECRET_SETTING" "$TENANT_ID_SETTING" 2>/dev/null; then
  log_info "App settings updated successfully"
  log_info "  AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}"
  log_info "  AZURE_TENANT_ID: ${AZURE_TENANT_ID}"
else
  log_error "Failed to set app settings"
  exit 1
fi

log_step "Verifying app settings..."
STORED_CLIENT_ID=$(az staticwebapp appsettings list --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query "properties.AZURE_CLIENT_ID" -o tsv 2>/dev/null || echo "not set")

log_step "Ensuring Web redirect URI and logout URL are configured..."
REDIRECT_URI="https://${SWA_HOSTNAME}/.auth/login/aad/callback"
LOGOUT_URL="https://${SWA_HOSTNAME}/.auth/logout"
APP_OBJECT_ID=$(az ad app show --id "${AZURE_CLIENT_ID}" --query id -o tsv)
CURRENT_WEB_URIS=$(az ad app show --id "${AZURE_CLIENT_ID}" --query "web.redirectUris" -o tsv | tr '\n' ' ')

if [[ "${CURRENT_WEB_URIS}" != *"${REDIRECT_URI}"* ]]; then
  az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
    --headers 'Content-Type=application/json' \
    --body "{\"web\":{\"redirectUris\":[\"${REDIRECT_URI}\"],\"logoutUrl\":\"${LOGOUT_URL}\",\"implicitGrantSettings\":{\"enableAccessTokenIssuance\":true,\"enableIdTokenIssuance\":true}},\"spa\":{\"redirectUris\":[]}}" \
    --output none
  log_info "Web redirect URI set to ${REDIRECT_URI}"
  log_info "Front-channel logout URL set to ${LOGOUT_URL}"
else
  log_info "Web redirect URI already configured"
fi

log_step "Persisting captured configuration for diagnostics..."
GENERATED_CONFIG="${GENERATED_DIR}/staticwebapp-entraid.${STATIC_WEB_APP_NAME}.metadata.json"
cat > "${GENERATED_CONFIG}" <<EOF
{
  "tenantId": "${AZURE_TENANT_ID}",
  "clientId": "${AZURE_CLIENT_ID}",
  "redirectUri": "${REDIRECT_URI}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

if [[ -n "${LINKED_BACKEND_ID}" ]]; then
  log_step "Configuring linked Function App authentication..."
  FUNCTION_APP_RG=$(echo "${LINKED_BACKEND_ID}" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="resourceGroups"){print $(i+1); exit}}}')
  FUNCTION_APP_NAME=$(echo "${LINKED_BACKEND_ID}" | awk -F/ '{print $NF}')

  if [[ -n "${FUNCTION_APP_RG}" && -n "${FUNCTION_APP_NAME}" ]]; then
    az functionapp config appsettings set \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${FUNCTION_APP_RG}" \
      --settings AUTH_METHOD=azure_swa \
      --output none
    log_info "Set AUTH_METHOD=azure_swa on ${FUNCTION_APP_NAME}"
  else
    log_warn "Unable to parse Function App details from linked backend id"
  fi
else
  log_warn "No linked backend detected on Static Web App"
fi

log_info ""
log_info "========================================="
log_info "Configuration Complete"
log_info "========================================="
log_info "  SWA: ${STATIC_WEB_APP_NAME}"
log_info "  Client ID: ${STORED_CLIENT_ID:0:20}..."
log_info "  Config file: staticwebapp-entraid.config.json (with auth rules)"
log_info ""
log_info "IMPORTANT: Deployment Sequence"
log_info "================================"
log_info "This script (Phase 1) configures the SWA authentication."
log_info "You MUST now run Phase 2 to rebuild the frontend:"
log_info ""
log_info "Phase 2: Rebuild frontend with Entra ID enabled"
log_info "   VITE_AUTH_ENABLED=true AZURE_TENANT_ID=${AZURE_TENANT_ID} ./20-deploy-frontend.sh"
log_info ""
log_info "Or, if your tenant ID is in your Azure CLI context, just:"
log_info "   VITE_AUTH_ENABLED=true ./20-deploy-frontend.sh"
log_info ""
log_info "After frontend rebuild, test in browser:"
log_info "   - Access SWA URL (shown in deployment output)"
log_info "   - You should be redirected to Entra ID login"
log_info "   - After login, frontend displays authenticated user"
log_info ""
log_info "Verify API calls include authentication:"
log_info "   - Check browser Network tab for x-ms-client-principal header"
log_info "   - Backend receives authenticated requests from SWA"
log_info ""
log_info "Configuration Details:"
log_info "   - SWA enforces authentication at the edge"
log_info "   - All requests must include valid Entra ID token"
log_info "   - SWA injects x-ms-client-principal header to backend"
log_info "   - Frontend can access user info via /.auth/me endpoint"
