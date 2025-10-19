#!/usr/bin/env bash
#
# 61-entraid-debug.sh - Debug Entra ID SWA Login Issues
#
# Comprehensive debugging script to diagnose why SWA login is failing
# even when the app registration looks correct.
#
# Usage:
#   ./61-entraid-debug.sh                                    # Interactive
#   ./61-entraid-debug.sh --app-id <id> --swa-name <name>  # Specific app/SWA
#

set -euo pipefail

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

APP_ID=""
SWA_NAME=""
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="$2"; shift 2 ;;
    --swa-name) SWA_NAME="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

echo ""
log_step "Entra ID SWA Login Debugging"
echo ""

# ==============================================================================
# Step 1: Check SWA and get app ID
# ==============================================================================

if [[ -z "${SWA_NAME}" ]]; then
  if [[ -z "${RESOURCE_GROUP}" ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
  fi

  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${SWA_COUNT}" -eq 1 ]]; then
    SWA_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  fi
fi

if [[ -z "${SWA_NAME}" ]]; then
  log_error "SWA not found or specified"
  exit 1
fi

log_info "Static Web App: ${SWA_NAME}"

# Get SWA details
SWA_HOSTNAME=$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)
SWA_URL="https://${SWA_HOSTNAME}"

log_info "URL: ${SWA_URL}"

# ==============================================================================
# Step 2: Get app settings from SWA
# ==============================================================================

log_step "Checking SWA App Settings..."
echo ""

APP_SETTINGS=$(az staticwebapp appsettings list --name "${SWA_NAME}" --resource-group "${RESOURCE_GROUP}" --query properties -o json)

SWA_CLIENT_ID=$(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_ID // empty')
SWA_CLIENT_SECRET_SET=$(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_SECRET // empty' | wc -c)

if [[ -n "${SWA_CLIENT_ID}" ]]; then
  log_success "AZURE_CLIENT_ID set: ${SWA_CLIENT_ID}"
  APP_ID="${SWA_CLIENT_ID}"
else
  log_error "AZURE_CLIENT_ID not set in SWA"
fi

if [[ "${SWA_CLIENT_SECRET_SET}" -gt 1 ]]; then
  log_success "AZURE_CLIENT_SECRET set: (${SWA_CLIENT_SECRET_SET} chars)"
else
  log_error "AZURE_CLIENT_SECRET not set in SWA"
fi

# ==============================================================================
# Step 3: Check app registration vs SWA settings
# ==============================================================================

if [[ -z "${APP_ID}" ]]; then
  log_error "Cannot continue - no APP_ID found"
  exit 1
fi

log_step "Checking App Registration..."
echo ""

APP_INFO=$(az ad app show --id "${APP_ID}" -o json 2>/dev/null || echo "{}")

if [[ -z "$(echo "${APP_INFO}" | jq -r '.appId // empty')" ]]; then
  log_error "App registration not found: ${APP_ID}"
  exit 1
fi

APP_NAME=$(echo "${APP_INFO}" | jq -r '.displayName')
log_success "App Name: ${APP_NAME}"

# ==============================================================================
# Step 4: Check OAuth flow endpoints
# ==============================================================================

log_step "Checking OAuth 2.0 Endpoints..."
echo ""

TENANT_ID=$(az account show --query tenantId -o tsv)
TENANT_DOMAIN=$(az ad signed-in-user show --query userPrincipalName -o tsv | sed 's/.*@//')

AUTHORIZE_ENDPOINT="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/authorize"
TOKEN_ENDPOINT="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"

log_info "Authorization Endpoint: ${AUTHORIZE_ENDPOINT}"
log_info "Token Endpoint: ${TOKEN_ENDPOINT}"
log_info "Tenant Domain: ${TENANT_DOMAIN}"

# ==============================================================================
# Step 5: Check redirect URI match
# ==============================================================================

log_step "Checking Redirect URI Configuration..."
echo ""

WEB_URIS=$(echo "${APP_INFO}" | jq -r '.web.redirectUris[]? // empty')
EXPECTED_URI="${SWA_URL}/.auth/login/aad/callback"

if echo "${WEB_URIS}" | grep -q "${SWA_HOSTNAME}/.auth/login/aad/callback"; then
  log_success "Redirect URI matches SWA:"
  log_info "  Expected: ${EXPECTED_URI}"
  log_info "  Registered: ${WEB_URIS}"
else
  log_error "Redirect URI MISMATCH!"
  log_warn "  Expected: ${EXPECTED_URI}"
  log_warn "  Registered: ${WEB_URIS}"
  log_info ""
  log_info "Fix with:"
  log_info "  ./60-entraid-user-setup.sh --fix-redirects --app-id ${APP_ID} --swa-hostname ${SWA_HOSTNAME}"
fi

# ==============================================================================
# Step 6: Check implicit grant
# ==============================================================================

log_step "Checking Implicit Grant Settings..."
echo ""

ID_TOKEN=$(echo "${APP_INFO}" | jq -r '.web.implicitGrantSettings.enableIdTokenIssuance')
ACCESS_TOKEN=$(echo "${APP_INFO}" | jq -r '.web.implicitGrantSettings.enableAccessTokenIssuance')

if [[ "${ID_TOKEN}" == "true" ]]; then log_success "ID Token Issuance: enabled"; else log_error "ID Token Issuance: DISABLED"; fi
if [[ "${ACCESS_TOKEN}" == "true" ]]; then log_success "Access Token Issuance: enabled"; else log_error "Access Token Issuance: DISABLED"; fi

# ==============================================================================
# Step 7: Check token version
# ==============================================================================

log_step "Checking Token Version..."
echo ""

TOKEN_VERSION=$(echo "${APP_INFO}" | jq -r '.api.requestedAccessTokenVersion // "null"')

if [[ "${TOKEN_VERSION}" == "2" ]]; then log_success "Token Version: 2"; else log_error "Token Version: ${TOKEN_VERSION} (should be 2)"; fi

# ==============================================================================
# Step 8: Check admin consent
# ==============================================================================

log_step "Checking Admin Consent Status..."
echo ""

SIGN_IN_NAMES=$(echo "${APP_INFO}" | jq -r '.signInAudience // "unknown"')
log_info "Sign-in Audience: ${SIGN_IN_NAMES}"

# Try to check if admin consent was granted via service principal
SP=$(az ad sp show --id "${APP_ID}" 2>/dev/null || echo "{}")
if [[ -n "$(echo "${SP}" | jq -r '.id // empty')" ]]; then
  log_success "Service Principal exists (admin consent may be granted)"
else
  log_warn "Service Principal not found (admin consent may not be granted)"
  log_info ""
  log_info "Grant admin consent with:"
  log_info "  ./60-entraid-user-setup.sh --admin-consent --app-id ${APP_ID}"
fi

# ==============================================================================
# Step 9: Check SWA readiness
# ==============================================================================

log_step "Checking SWA Deployment..."
echo ""

SWA_STATE=$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${RESOURCE_GROUP}" --query properties.provisioningState -o tsv 2>/dev/null)
SWA_STATUS=$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${RESOURCE_GROUP}" --query properties.buildProperties.provisioningState -o tsv 2>/dev/null || echo "unknown")

log_info "SWA Provisioning State: ${SWA_STATE}"
log_info "SWA Build State: ${SWA_STATUS}"

if [[ "${SWA_STATE}" == "Succeeded" ]]; then
  log_success "SWA is fully provisioned"
else
  log_warn "SWA provisioning may be incomplete: ${SWA_STATE}"
fi

# ==============================================================================
# Summary and Recommendations
# ==============================================================================

echo ""
log_step "Summary & Recommendations"
echo ""

ISSUES=0

# Check all critical items
if [[ "${ID_TOKEN}" != "true" ]]; then
  ((ISSUES++))
  log_error "ISSUE 1: ID Token Issuance not enabled"
fi

if [[ "${ACCESS_TOKEN}" != "true" ]]; then
  ((ISSUES++))
  log_error "ISSUE 2: Access Token Issuance not enabled"
fi

if [[ "${TOKEN_VERSION}" != "2" ]]; then
  ((ISSUES++))
  log_error "ISSUE 3: Token version is ${TOKEN_VERSION}, should be 2"
fi

if ! echo "${WEB_URIS}" | grep -q "${SWA_HOSTNAME}"; then
  ((ISSUES++))
  log_error "ISSUE 4: Redirect URI doesn't match SWA hostname"
fi

if [[ -z "$(echo "${SP}" | jq -r '.id // empty')" ]]; then
  ((ISSUES++))
  log_warn "ISSUE 5: Admin consent may not be granted"
fi

if [[ "${SWA_STATE}" != "Succeeded" ]]; then
  ((ISSUES++))
  log_error "ISSUE 6: SWA not fully provisioned"
fi

echo ""
if [[ ${ISSUES} -eq 0 ]]; then
  log_success "All checks passed! Configuration looks correct."
  echo ""
  log_info "If login still fails, try:"
  log_info "  1. Clear browser cache for azurestaticapps.net"
  log_info "  2. Try incognito/private mode"
  log_info "  3. Check browser console (F12) for errors"
  log_info "  4. Verify user account is enabled in Entra ID"
  log_info ""
  log_info "To see full app registration details:"
  log_info "  az ad app show --id ${APP_ID} | jq"
else
  log_warn "Found ${ISSUES} issue(s) that need to be fixed"
fi

echo ""
log_success "Debug complete!"
