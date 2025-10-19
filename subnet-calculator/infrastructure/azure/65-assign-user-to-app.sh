#!/usr/bin/env bash
#
# Assign User to Entra ID App Registration
#
# This script assigns a user to an Entra ID app registration (Enterprise Application)
# to allow them to authenticate. Required for single-tenant (AzureADMyOrg) apps.
#
# Usage:
#   # Auto-detect everything
#   ./65-assign-user-to-app.sh
#
#   # Specify user and app
#   APP_ID=<client-id> USER_UPN=swatest@example.com ./65-assign-user-to-app.sh
#
# Parameters:
#   APP_ID      - Entra ID app registration client ID (auto-detected from SWA)
#   USER_UPN    - User Principal Name (e.g., user@example.com)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - User must have permissions to assign users to applications
#   - App registration must exist

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
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

TENANT_ID=$(az account show --query tenantId -o tsv)
log_info "Tenant: ${TENANT_ID}"

# Auto-detect or prompt for APP_ID
if [[ -z "${APP_ID:-}" ]]; then
  log_info "Detecting Entra ID app from SWA settings..."

  # Try to find resource group with Entra ID SWA
  RESOURCE_GROUP=$(az staticwebapp list --query "[?contains(name, 'entraid')].resourceGroup | [0]" -o tsv 2>/dev/null || echo "")

  if [[ -n "${RESOURCE_GROUP}" ]]; then
    SWA_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'entraid')].name | [0]" -o tsv)
    APP_ID=$(az staticwebapp appsettings list --name "${SWA_NAME}" --resource-group "${RESOURCE_GROUP}" --query "properties.AZURE_CLIENT_ID" -o tsv 2>/dev/null || echo "")

    if [[ -n "${APP_ID}" ]]; then
      log_info "Auto-detected app ID from SWA: ${APP_ID}"
    fi
  fi
fi

if [[ -z "${APP_ID:-}" ]]; then
  read -r -p "Enter Entra ID App Client ID: " APP_ID
  if [[ -z "${APP_ID}" ]]; then
    log_error "App ID is required"
    exit 1
  fi
fi

# Auto-detect or prompt for USER_UPN
if [[ -z "${USER_UPN:-}" ]]; then
  # Try common test user
  USER_UPN="swatest@akscicdpipelines.onmicrosoft.com"

  if ! az ad user show --id "${USER_UPN}" &>/dev/null 2>&1; then
    # Try to auto-detect tenant domain
    TENANT_DOMAIN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null | sed 's/.*@//' || echo "")
    if [[ -n "${TENANT_DOMAIN}" ]]; then
      USER_UPN="swatest@${TENANT_DOMAIN}"
    fi
  fi

  # Verify user exists
  if ! az ad user show --id "${USER_UPN}" &>/dev/null 2>&1; then
    log_warn "Default user ${USER_UPN} not found"
    read -r -p "Enter User Principal Name (email): " USER_UPN
  else
    log_info "Auto-detected user: ${USER_UPN}"
  fi
fi

if [[ -z "${USER_UPN}" ]]; then
  log_error "User UPN is required"
  exit 1
fi

# Get user object ID
log_step "Looking up user..."
USER_OBJECT_ID=$(az ad user show --id "${USER_UPN}" --query id -o tsv 2>/dev/null || echo "")

if [[ -z "${USER_OBJECT_ID}" ]]; then
  log_error "User ${USER_UPN} not found in Entra ID"
  exit 1
fi

USER_DISPLAY_NAME=$(az ad user show --id "${USER_UPN}" --query displayName -o tsv)
log_info "Found user: ${USER_DISPLAY_NAME} (${USER_UPN})"
log_info "User Object ID: ${USER_OBJECT_ID}"

# Get app details
log_step "Looking up app registration..."
APP_INFO=$(az ad app show --id "${APP_ID}" 2>/dev/null || echo "{}")

if [[ "$(echo "${APP_INFO}" | jq 'length')" -eq 0 ]]; then
  log_error "App ${APP_ID} not found"
  exit 1
fi

APP_NAME=$(echo "${APP_INFO}" | jq -r '.displayName')
log_info "Found app: ${APP_NAME}"

# Get the service principal (Enterprise Application) for this app
# The app registration and service principal are different objects!
log_step "Looking up Enterprise Application (Service Principal)..."
SERVICE_PRINCIPAL_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [[ -z "${SERVICE_PRINCIPAL_ID}" ]]; then
  log_warn "Enterprise Application not found for this app registration"
  log_info "Creating Enterprise Application (Service Principal)..."

  SERVICE_PRINCIPAL_ID=$(az ad sp create --id "${APP_ID}" --query id -o tsv)
  log_success "Enterprise Application created: ${SERVICE_PRINCIPAL_ID}"
else
  log_info "Enterprise Application ID: ${SERVICE_PRINCIPAL_ID}"
fi

# Check if user is already assigned
log_step "Checking existing assignments..."
EXISTING_ASSIGNMENT=$(az rest \
  --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/${SERVICE_PRINCIPAL_ID}/appRoleAssignedTo" \
  --query "value[?principalId=='${USER_OBJECT_ID}'].id | [0]" -o tsv 2>/dev/null || echo "")

if [[ -n "${EXISTING_ASSIGNMENT}" ]]; then
  log_success "User ${USER_DISPLAY_NAME} is already assigned to ${APP_NAME}"
  log_info "Assignment ID: ${EXISTING_ASSIGNMENT}"
  exit 0
fi

# Get the default app role ID (this is required for assignment)
# Most apps have a default "User" role with a specific GUID
DEFAULT_ROLE_ID="00000000-0000-0000-0000-000000000000"

log_step "Assigning user to application..."
log_info "User: ${USER_DISPLAY_NAME} (${USER_UPN})"
log_info "App: ${APP_NAME}"
echo ""

# Assign the user using Microsoft Graph API
ASSIGNMENT_BODY=$(cat <<EOF
{
  "principalId": "${USER_OBJECT_ID}",
  "resourceId": "${SERVICE_PRINCIPAL_ID}",
  "appRoleId": "${DEFAULT_ROLE_ID}"
}
EOF
)

if az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/${SERVICE_PRINCIPAL_ID}/appRoleAssignedTo" \
  --headers "Content-Type=application/json" \
  --body "${ASSIGNMENT_BODY}" \
  --output none; then

  log_success "User assigned successfully!"
  echo ""
  log_info "========================================="
  log_info "Assignment Complete"
  log_info "========================================="
  log_info "User: ${USER_DISPLAY_NAME}"
  log_info "Email: ${USER_UPN}"
  log_info "App: ${APP_NAME}"
  log_info ""
  log_info "Next Steps:"
  log_info "1. Test login at your SWA:"
  log_info "   https://proud-bay-05b7e1c03.1.azurestaticapps.net"
  log_info ""
  log_info "2. Login with:"
  log_info "   Username: ${USER_UPN}"
  log_info "   Password: (the password you set for this user)"
  log_info ""
  log_info "3. After successful login, the app should display"
  log_info "   the authenticated user information"

else
  log_error "Failed to assign user to application"
  log_error "You may need to:"
  log_error "  1. Have admin permissions in Entra ID"
  log_error "  2. Grant consent for the app"
  log_error "  3. Assign the user manually through Azure Portal:"
  log_info "     Portal → Entra ID → Enterprise Applications → ${APP_NAME} → Users and groups → Add user"
  exit 1
fi
