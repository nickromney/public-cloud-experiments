#!/usr/bin/env bash
#
# 99-debug-entraid-permissions.sh - Debug Entra ID app registration and permissions
#
# Usage:
#   ./99-debug-entraid-permissions.sh <client-id>
#   ./99-debug-entraid-permissions.sh 0fd0e7ce-599e-4b95-9a62-e57d6a1c0d59
#
# This script checks:
#   - App registration configuration
#   - Redirect URIs and logout URL
#   - API permissions and consent status
#   - Service principal (enterprise app) settings
#   - Token configuration
#   - User assignment requirements
#   - Implicit grant settings

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
log_ok() { echo -e "${GREEN}[✓]${NC} $*"; }
log_fail() { echo -e "${RED}[✗]${NC} $*"; }

# Check prerequisites
if ! command -v az &>/dev/null; then
  log_error "Azure CLI not found"
  exit 1
fi

if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Get client ID from argument or prompt
CLIENT_ID="${1:-}"
if [[ -z "${CLIENT_ID}" ]]; then
  echo ""
  log_warn "No client ID provided"
  echo ""
  read -rp "Enter Entra ID Client ID (App ID): " CLIENT_ID
  if [[ -z "${CLIENT_ID}" ]]; then
    log_error "Client ID is required"
    exit 1
  fi
fi

echo ""
log_info "========================================="
log_info "Entra ID Permission Debugger"
log_info "========================================="
log_info "Client ID: ${CLIENT_ID}"
echo ""

# Get current tenant info
log_step "Current Azure Context"
TENANT_INFO=$(az account show --query "{tenantId:tenantId, tenantName:tenantDisplayName, user:user.name}" -o json)
TENANT_ID=$(echo "$TENANT_INFO" | jq -r '.tenantId')
TENANT_NAME=$(echo "$TENANT_INFO" | jq -r '.tenantName')
CURRENT_USER=$(echo "$TENANT_INFO" | jq -r '.user')

log_info "Tenant ID: ${TENANT_ID}"
log_info "Tenant Name: ${TENANT_NAME}"
log_info "Signed in as: ${CURRENT_USER}"
echo ""

# Check if app exists
log_step "Step 1: App Registration Basic Info"
if ! APP_INFO=$(az ad app show --id "${CLIENT_ID}" --query "{displayName:displayName, appId:appId, id:id, signInAudience:signInAudience}" -o json 2>/dev/null); then
  log_fail "App registration not found: ${CLIENT_ID}"
  exit 1
fi

APP_DISPLAY_NAME=$(echo "$APP_INFO" | jq -r '.displayName')
APP_OBJECT_ID=$(echo "$APP_INFO" | jq -r '.id')
SIGN_IN_AUDIENCE=$(echo "$APP_INFO" | jq -r '.signInAudience')

log_ok "App registration found"
log_info "  Display Name: ${APP_DISPLAY_NAME}"
log_info "  Object ID: ${APP_OBJECT_ID}"
log_info "  Sign-in Audience: ${SIGN_IN_AUDIENCE}"

# Explain sign-in audience
case "${SIGN_IN_AUDIENCE}" in
  "AzureADMyOrg")
    log_info "    → Only users in THIS tenant (${TENANT_NAME}) can sign in"
    ;;
  "AzureADMultipleOrgs")
    log_info "    → Users from ANY Azure AD tenant can sign in"
    ;;
  "AzureADandPersonalMicrosoftAccount")
    log_info "    → Users from any Azure AD tenant AND personal Microsoft accounts"
    ;;
  "PersonalMicrosoftAccount")
    log_info "    → Only personal Microsoft accounts"
    ;;
esac
echo ""

# Check redirect URIs
log_step "Step 2: Redirect URIs and Logout URL"
REDIRECT_INFO=$(az ad app show --id "${CLIENT_ID}" --query "{redirectUris:web.redirectUris, logoutUrl:web.logoutUrl}" -o json)
REDIRECT_URIS=$(echo "$REDIRECT_INFO" | jq -r '.redirectUris[]?' 2>/dev/null || echo "")
LOGOUT_URL=$(echo "$REDIRECT_INFO" | jq -r '.logoutUrl // "Not set"')

if [[ -n "${REDIRECT_URIS}" ]]; then
  log_ok "Redirect URIs configured:"
  echo "$REDIRECT_URIS" | while read -r uri; do
    [[ -n "$uri" ]] && log_info "  • $uri"
  done
else
  log_fail "No redirect URIs configured"
fi

log_info "Logout URL: ${LOGOUT_URL}"
echo ""

# Check implicit grant settings
log_step "Step 3: Implicit Grant Settings"
IMPLICIT_GRANT=$(az ad app show --id "${CLIENT_ID}" --query "web.implicitGrantSettings" -o json)
ACCESS_TOKEN_ENABLED=$(echo "$IMPLICIT_GRANT" | jq -r '.enableAccessTokenIssuance')
ID_TOKEN_ENABLED=$(echo "$IMPLICIT_GRANT" | jq -r '.enableIdTokenIssuance')

if [[ "${ACCESS_TOKEN_ENABLED}" == "true" ]]; then
  log_ok "Access tokens: Enabled"
else
  log_warn "Access tokens: Disabled (might be needed for some flows)"
fi

if [[ "${ID_TOKEN_ENABLED}" == "true" ]]; then
  log_ok "ID tokens: Enabled"
else
  log_fail "ID tokens: Disabled (REQUIRED for SWA authentication)"
fi
echo ""

# Check API permissions
log_step "Step 4: API Permissions"
PERMISSIONS=$(az ad app permission list --id "${CLIENT_ID}" -o json)

if [[ "$(echo "$PERMISSIONS" | jq 'length')" -eq 0 ]]; then
  log_warn "No API permissions configured"
else
  log_ok "API permissions found:"
  echo "$PERMISSIONS" | jq -r '.[] | .resourceAppId as $appId | .resourceAccess[] | "  • Permission ID: \(.id) (Type: \(.type))"'

  # Check for Microsoft Graph User.Read (most common)
  USER_READ_ID="e1fe6dd8-ba31-4d61-89e7-88639da4683d"
  if echo "$PERMISSIONS" | jq -e ".[] | select(.resourceAccess[].id == \"${USER_READ_ID}\")" >/dev/null 2>&1; then
    log_info "    Contains Microsoft Graph User.Read permission"
  fi
fi
echo ""

# Check service principal (enterprise app)
log_step "Step 5: Service Principal (Enterprise App)"
SP_ID=$(az ad sp list --filter "appId eq '${CLIENT_ID}'" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [[ -z "${SP_ID}" ]]; then
  log_fail "Service principal not found"
  log_warn "This means the app has NOT been consented to in this tenant"
  log_info "To fix: Run 'az ad app permission admin-consent --id ${CLIENT_ID}'"
else
  log_ok "Service principal found: ${SP_ID}"

  # Check user assignment requirement
  SP_INFO=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_ID}" --query "{appRolesAssignmentRequired:appRolesAssignmentRequired, displayName:displayName}" -o json)
  USER_ASSIGNMENT_REQUIRED=$(echo "$SP_INFO" | jq -r '.appRolesAssignmentRequired // false')

  if [[ "${USER_ASSIGNMENT_REQUIRED}" == "true" ]]; then
    log_warn "User assignment required: YES"
    log_info "  → Only explicitly assigned users can sign in"
    log_info "  → To assign users: Azure Portal → Enterprise Applications → ${APP_DISPLAY_NAME} → Users and groups"
  else
    log_ok "User assignment required: NO (all tenant users can sign in)"
  fi

  # Check consent status
  log_info "Checking admin consent status..."
  OAUTH_GRANTS=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?\$filter=clientId eq '${SP_ID}'" \
    --query "value[0].scope" -o tsv 2>/dev/null || echo "")

  if [[ -n "${OAUTH_GRANTS}" ]]; then
    log_ok "Admin consent granted for: ${OAUTH_GRANTS}"
  else
    log_warn "Admin consent status unclear"
    log_info "To grant consent: az ad app permission admin-consent --id ${CLIENT_ID}"
  fi
fi
echo ""

# Check token configuration
log_step "Step 6: Token Configuration"
TOKEN_CONFIG=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
  --query "{accessTokenAcceptedVersion:api.requestedAccessTokenVersion, optionalClaims:optionalClaims}" -o json 2>/dev/null || echo '{}')

TOKEN_VERSION=$(echo "$TOKEN_CONFIG" | jq -r '.accessTokenAcceptedVersion // "1 (default)"')
log_info "Access token version: ${TOKEN_VERSION}"

if [[ "${TOKEN_VERSION}" == "2" ]]; then
  log_ok "Using v2.0 tokens (recommended)"
elif [[ "${TOKEN_VERSION}" == "null" ]] || [[ "${TOKEN_VERSION}" == "1 (default)" ]]; then
  log_info "Using v1.0 tokens (default for older apps)"
fi

OPTIONAL_CLAIMS=$(echo "$TOKEN_CONFIG" | jq -r '.optionalClaims // "None configured"')
if [[ "${OPTIONAL_CLAIMS}" != "None configured" ]]; then
  log_info "Optional claims: Configured"
else
  log_info "Optional claims: None"
fi
echo ""

# List users in tenant (helpful for debugging)
log_step "Step 7: Users in Tenant"
log_info "Listing first 10 users in ${TENANT_NAME}..."
az ad user list --query "[0:9].{displayName:displayName, userPrincipalName:userPrincipalName}" -o table
echo ""

# Check if there are any assigned users (if service principal exists)
if [[ -n "${SP_ID}" ]]; then
  log_step "Step 8: Assigned Users (if user assignment required)"
  ASSIGNED_USERS=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_ID}/appRoleAssignedTo" \
    --query "value[].{principalDisplayName:principalDisplayName, principalType:principalType}" -o json 2>/dev/null || echo '[]')

  USER_COUNT=$(echo "$ASSIGNED_USERS" | jq 'length')
  if [[ "${USER_COUNT}" -gt 0 ]]; then
    log_info "Found ${USER_COUNT} assigned users/groups:"
    echo "$ASSIGNED_USERS" | jq -r '.[] | "  • \(.principalDisplayName) (\(.principalType))"'
  else
    if [[ "${USER_ASSIGNMENT_REQUIRED}" == "true" ]]; then
      log_warn "User assignment required but NO users assigned!"
      log_info "Users must be assigned in Azure Portal → Enterprise Applications"
    else
      log_info "No explicit user assignments (not required)"
    fi
  fi
  echo ""
fi

# Summary
log_info "========================================="
log_info "Summary and Recommendations"
log_info "========================================="
echo ""

ISSUES_FOUND=0

# Check 1: Service principal exists
if [[ -z "${SP_ID}" ]]; then
  log_fail "Issue: App not consented in tenant"
  log_info "  Fix: az ad app permission admin-consent --id ${CLIENT_ID}"
  ((ISSUES_FOUND++))
fi

# Check 2: ID token enabled
if [[ "${ID_TOKEN_ENABLED}" != "true" ]]; then
  log_fail "Issue: ID token issuance disabled"
  log_info "  Fix: Enable in Azure Portal → App registrations → Authentication → Implicit grant"
  ((ISSUES_FOUND++))
fi

# Check 3: Redirect URIs exist
if [[ -z "${REDIRECT_URIS}" ]]; then
  log_fail "Issue: No redirect URIs configured"
  log_info "  Fix: Add redirect URIs in Azure Portal → App registrations → Authentication"
  ((ISSUES_FOUND++))
fi

# Check 4: User assignment issues
if [[ "${USER_ASSIGNMENT_REQUIRED}" == "true" ]] && [[ "${USER_COUNT:-0}" -eq 0 ]]; then
  log_fail "Issue: User assignment required but no users assigned"
  log_info "  Fix: Assign users in Azure Portal → Enterprise Applications → Users and groups"
  ((ISSUES_FOUND++))
fi

if [[ ${ISSUES_FOUND} -eq 0 ]]; then
  log_ok "No obvious configuration issues found"
  echo ""
  log_info "If authentication still fails, check:"
  log_info "  1. SWA app settings have correct AZURE_CLIENT_ID and AZURE_CLIENT_SECRET"
  log_info "  2. staticwebapp.config.json has correct tenant ID in openIdIssuer"
  log_info "  3. Browser console for specific error messages"
  log_info "  4. Azure Portal → Entra ID → Sign-in logs for detailed errors"
else
  echo ""
  log_warn "Found ${ISSUES_FOUND} potential issue(s) - see recommendations above"
fi

echo ""
log_info "Done"
