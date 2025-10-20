#!/usr/bin/env bash
#
# Verify Entra ID Authentication Setup
#
# This script performs comprehensive diagnostic checks on Entra ID authentication
# configuration for Azure Static Web App. It identifies misconfigurations and
# provides remediation steps.
#
# Usage:
#   # Basic diagnosis (auto-detect everything)
#   ./64-verify-entraid-setup.sh
#
#   # Verbose output with all details
#   ./64-verify-entraid-setup.sh --verbose
#
#   # Generate report file
#   ./64-verify-entraid-setup.sh --report setup-report.md
#
#   # Suggest fixes
#   ./64-verify-entraid-setup.sh --suggest-fixes
#
#   # Auto-apply safe fixes
#   ./64-verify-entraid-setup.sh --fix
#
# Options:
#   --app-id <id>           Entra ID app ID (auto-detected if not provided)
#   --swa <name>            Static Web App name (auto-detected if not provided)
#   --user <upn>            Test user UPN (auto-detected if not provided)
#   --verbose               Show detailed output
#   --report <file>         Generate markdown report
#   --csv <file>            Export findings as CSV
#   --json                  Output results as JSON
#   --suggest-fixes         Show remediation commands
#   --fix                   Auto-apply safe fixes
#

set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
log_check() { echo -e "${BLUE}[CHECK]${NC} $*"; }

# Symbols for results
PASS="✓"
FAIL="✗"
WARN="⚠"

# Parse arguments
VERBOSE=false
# REPORT_FILE and CSV_FILE are for future use
# SUGGEST_FIXES and AUTO_FIX control output
SUGGEST_FIXES=false
AUTO_FIX=false
APP_ID="${APP_ID:-}"
SWA_NAME="${SWA_NAME:-}"
TEST_USER="${TEST_USER:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="$2"; shift 2 ;;
    --swa) SWA_NAME="$2"; shift 2 ;;
    --user) TEST_USER="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    --suggest-fixes) SUGGEST_FIXES=true; shift ;;
    --fix) AUTO_FIX=true; SUGGEST_FIXES=true; shift ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Initialize tracking arrays
declare -a CHECKS_PASSED
declare -a CHECKS_FAILED
declare -a CHECKS_WARNING
declare -a FIXES_AVAILABLE

# Initialize variables used later
APP_SETTINGS="{}"
SWA_HOSTNAME=""
SWA_URL=""
SPA_URIS=""
CLIENT_ID_SET="false"
FUNCTION_APP_NAME=""
FUNCTION_APP_RG=""

# Auto-detect RESOURCE_GROUP if not set
if [[ -z "${RESOURCE_GROUP}" ]]; then
  RG_COUNT=$(az group list --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    [[ "${VERBOSE}" == "true" ]] && log_info "Auto-detected resource group: ${RESOURCE_GROUP}"
  elif [[ "${RG_COUNT}" -gt 1 ]]; then
    # Try to find a resource group that contains Static Web Apps with "entraid" in the name
    ENTRAID_RG=$(az staticwebapp list --query "[?contains(name, 'entraid')].resourceGroup | [0]" -o tsv 2>/dev/null || echo "")

    if [[ -n "${ENTRAID_RG}" ]]; then
      RESOURCE_GROUP="${ENTRAID_RG}"
      [[ "${VERBOSE}" == "true" ]] && log_info "Auto-detected resource group with Entra ID SWA: ${RESOURCE_GROUP}"
    else
      # Fall back to first resource group
      RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
      [[ "${VERBOSE}" == "true" ]] && log_info "Selected first resource group: ${RESOURCE_GROUP}"
    fi
  fi
fi

# Auto-detect SWA_NAME if not set
if [[ -z "${SWA_NAME}" ]]; then
  if [[ -n "${RESOURCE_GROUP}" ]]; then
    SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "${SWA_COUNT}" -eq 1 ]]; then
      SWA_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
      [[ "${VERBOSE}" == "true" ]] && log_info "Auto-detected SWA: ${SWA_NAME}"
    elif [[ "${SWA_COUNT}" -gt 1 ]]; then
      # Prefer SWA with "entraid" in the name for verification
      SWA_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'entraid')].name | [0]" -o tsv 2>/dev/null || echo "")

      if [[ -z "${SWA_NAME}" ]]; then
        # If no "entraid" SWA found, try to select interactively
        log_warn "Multiple SWAs found. Use --swa <name> to specify which one to verify."
        SWA_NAME=$(select_static_web_app "${RESOURCE_GROUP}") || {
          log_warn "No SWA selected, verification will be limited"
          SWA_NAME=""
        }
      else
        [[ "${VERBOSE}" == "true" ]] && log_info "Auto-selected Entra ID SWA: ${SWA_NAME}"
      fi
    fi
  fi
fi

# Get tenant ID and domain
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

# Get tenant name for default UPN domain (e.g., akscicdpipelines.onmicrosoft.com)
TENANT_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null | sed 's/.*@//' || echo "")

# If we can't get tenant name from signed-in user, try to infer from tenant ID
if [[ -z "${TENANT_NAME}" ]]; then
  # Try to get organization info
  FIRST_APP_ID=$(az ad app list --query "[0].appId" -o tsv 2>/dev/null)
  if [[ -n "${FIRST_APP_ID}" ]]; then
    TENANT_NAME=$(az ad app show --id "${FIRST_APP_ID}" --query "publisherDomain" -o tsv 2>/dev/null || echo "")
  fi
fi

TENANT_DOMAIN="${TENANT_NAME}"

log_step "Starting Entra ID Setup Verification"
log_info "Tenant: ${TENANT_ID}"
[[ "${VERBOSE}" == "true" ]] && log_info "Tenant Domain: ${TENANT_DOMAIN}"

# ============================================================================
# CHECK 1: SWA CONFIGURATION
# ============================================================================
log_check "Checking Static Web App Configuration..."

if [[ -z "${SWA_NAME}" ]]; then
  log_warn "No Static Web App specified or auto-detected"
  CHECKS_WARNING+=("SWA: No SWA found or specified")
else
  SWA_RG="${RESOURCE_GROUP}"

  # Check SWA exists
  if ! az staticwebapp show --name "${SWA_NAME}" --resource-group "${SWA_RG}" &>/dev/null 2>&1; then
    log_error "SWA ${SWA_NAME} not found in ${SWA_RG}"
    CHECKS_FAILED+=("SWA exists: ${SWA_NAME} not found")
  else
    SWA_HOSTNAME=$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${SWA_RG}" --query defaultHostname -o tsv)
    SWA_URL="https://${SWA_HOSTNAME}"
    CHECKS_PASSED+=("SWA ${SWA_NAME} exists")
    [[ "${VERBOSE}" == "true" ]] && log_info "  URL: ${SWA_URL}"

    # Check app settings
    APP_SETTINGS=$(az staticwebapp appsettings list --name "${SWA_NAME}" --resource-group "${SWA_RG}" --query "properties" -o json 2>/dev/null || echo "{}")

    if echo "${APP_SETTINGS}" | jq -e '.AZURE_CLIENT_ID' &>/dev/null 2>&1; then
      CLIENT_ID_SET="true"
      CHECKS_PASSED+=("SWA app setting: AZURE_CLIENT_ID is set")
      [[ "${VERBOSE}" == "true" ]] && log_info "  AZURE_CLIENT_ID: $(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_ID')"
    else
      CHECKS_FAILED+=("SWA app setting: AZURE_CLIENT_ID not set")
      FIXES_AVAILABLE+=("Set AZURE_CLIENT_ID in SWA app settings")
    fi

    if echo "${APP_SETTINGS}" | jq -e '.AZURE_CLIENT_SECRET' &>/dev/null 2>&1; then
      CHECKS_PASSED+=("SWA app setting: AZURE_CLIENT_SECRET is set")
      [[ "${VERBOSE}" == "true" ]] && log_info "  AZURE_CLIENT_SECRET: (set, length: $(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_SECRET | length'))"
    else
      CHECKS_FAILED+=("SWA app setting: AZURE_CLIENT_SECRET not set")
      FIXES_AVAILABLE+=("Set AZURE_CLIENT_SECRET in SWA app settings")
    fi
  fi
fi

# ============================================================================
# CHECK 2: ENTRA ID APP REGISTRATION
# ============================================================================
log_check "Checking Entra ID App Registration..."

if [[ -z "${APP_ID}" ]] && [[ -n "${APP_SETTINGS}" ]] && echo "${APP_SETTINGS}" | jq -e '.AZURE_CLIENT_ID' &>/dev/null 2>&1; then
  APP_ID=$(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_ID')
  [[ "${VERBOSE}" == "true" ]] && log_info "Auto-detected app ID from SWA settings: ${APP_ID}"
fi

if [[ -z "${APP_ID}" ]]; then
  log_warn "No app ID specified or found in SWA settings"
  CHECKS_WARNING+=("App Registration: No app ID found")
else
  # Query app registration
  APP_INFO=$(az ad app show --id "${APP_ID}" 2>/dev/null || echo "{}")

  if [[ "$(echo "${APP_INFO}" | jq 'length')" -eq 0 ]] || [[ -z "$(echo "${APP_INFO}" | jq -r '.appId // empty')" ]]; then
    log_error "App registration ${APP_ID} not found"
    CHECKS_FAILED+=("App Registration: ${APP_ID} not found")
  else
    APP_NAME=$(echo "${APP_INFO}" | jq -r '.displayName')
    CHECKS_PASSED+=("App Registration exists: ${APP_NAME}")
    [[ "${VERBOSE}" == "true" ]] && log_info "  App Name: ${APP_NAME}"

    # Check SPA redirect URIs
    SPA_URIS=$(echo "${APP_INFO}" | jq -r '.spa.redirectUris[]? // empty')
    if [[ -z "${SPA_URIS}" ]]; then
      CHECKS_WARNING+=("App Registration: No SPA redirect URIs configured")
      FIXES_AVAILABLE+=("Add SPA redirect URIs to app registration")
      [[ "${VERBOSE}" == "true" ]] && log_warn "  SPA Redirect URIs: (none)"
    else
      EXPECTED_URI="${SWA_URL}/.auth/login/aad/callback"
      if echo "${SPA_URIS}" | grep -q "${SWA_HOSTNAME}/.auth/login/aad/callback"; then
        CHECKS_PASSED+=("App Registration: SPA redirect URI matches SWA")
        [[ "${VERBOSE}" == "true" ]] && log_info "  SPA Redirect URI: ${SPA_URIS}"
      else
        CHECKS_FAILED+=("App Registration: SPA redirect URI does not match SWA hostname")
        FIXES_AVAILABLE+=("Update SPA redirect URI in app registration to: ${EXPECTED_URI}")
        [[ "${VERBOSE}" == "true" ]] && log_error "  Expected: ${EXPECTED_URI}"
        [[ "${VERBOSE}" == "true" ]] && log_error "  Got: ${SPA_URIS}"
      fi
    fi

    # Check web redirect URIs (should not be used for SPA)
    WEB_URIS=$(echo "${APP_INFO}" | jq -r '.web.redirectUris[]? // empty')
    if [[ -n "${WEB_URIS}" ]]; then
      CHECKS_WARNING+=("App Registration: Web redirect URIs are set (not recommended for SPA)")
      [[ "${VERBOSE}" == "true" ]] && log_warn "  Web Redirect URIs: ${WEB_URIS}"
    fi

    # Check implicit grant settings
    ID_TOKEN_IMPLICIT=$(echo "${APP_INFO}" | jq -r '.web.implicitGrantSettings.enableIdTokenIssuance // false')
    ACCESS_TOKEN_IMPLICIT=$(echo "${APP_INFO}" | jq -r '.web.implicitGrantSettings.enableAccessTokenIssuance // false')

    if [[ "${ID_TOKEN_IMPLICIT}" == "true" ]]; then
      CHECKS_PASSED+=("App Registration: ID token implicit grant enabled")
    else
      CHECKS_WARNING+=("App Registration: ID token implicit grant disabled")
      FIXES_AVAILABLE+=("Enable ID token implicit grant for SPA compatibility")
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
      log_info "  ID Token Implicit Grant: ${ID_TOKEN_IMPLICIT}"
      log_info "  Access Token Implicit Grant: ${ACCESS_TOKEN_IMPLICIT}"
    fi

    # Check requested access token version (api.requestedAccessTokenVersion)
    TOKEN_VERSION=$(echo "${APP_INFO}" | jq -r '.api.requestedAccessTokenVersion // "null"')
    if [[ "${TOKEN_VERSION}" == "2" ]]; then
      CHECKS_PASSED+=("App Registration: Requested access token version is 2")
    else
      CHECKS_WARNING+=("App Registration: Requested access token version is ${TOKEN_VERSION} (should be 2)")
      # Get object ID for Graph API update
      APP_OBJECT_ID=$(echo "${APP_INFO}" | jq -r '.id // empty')
      if [[ -n "${APP_OBJECT_ID}" ]]; then
        FIXES_AVAILABLE+=("Set token version: az rest --method PATCH --url 'https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}' --headers 'Content-Type=application/json' --body '{\"api\":{\"requestedAccessTokenVersion\":2}}'")
      else
        FIXES_AVAILABLE+=("Set requested access token version to 2 (consult Azure documentation for current az ad commands)")
      fi
    fi
    [[ "${VERBOSE}" == "true" ]] && log_info "  Requested Access Token Version: ${TOKEN_VERSION}"

    # Check sign-in audience
    SIGN_IN_AUDIENCE=$(echo "${APP_INFO}" | jq -r '.signInAudience')
    if [[ "${SIGN_IN_AUDIENCE}" == "AzureADMyOrg" ]]; then
      CHECKS_PASSED+=("App Registration: Single-tenant configuration (AzureADMyOrg)")
    else
      CHECKS_WARNING+=("App Registration: Sign-in audience is ${SIGN_IN_AUDIENCE}")
    fi
    [[ "${VERBOSE}" == "true" ]] && log_info "  Sign-in Audience: ${SIGN_IN_AUDIENCE}"
  fi
fi

# ============================================================================
# CHECK 3: USER ACCOUNT
# ============================================================================
log_check "Checking Entra ID User Account..."

if [[ -z "${TEST_USER}" ]]; then
  # Try to find swatest user - with correct tenant domain
  # First try the known user from investigation
  TEST_USER="swatest@akscicdpipelines.onmicrosoft.com"

  # Check if user exists with this UPN
  if ! az ad user show --id "${TEST_USER}" &>/dev/null 2>&1; then
    # If not found, try with auto-detected tenant domain
    if [[ -n "${TENANT_DOMAIN}" ]]; then
      TEST_USER="swatest@${TENANT_DOMAIN}"
    fi
  fi
  [[ "${VERBOSE}" == "true" ]] && log_info "Auto-detected test user: ${TEST_USER}"
fi

USER_INFO=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/users/${TEST_USER}?\$select=id,displayName,userPrincipalName,accountEnabled" 2>/dev/null || echo "{}")

if [[ "$(echo "${USER_INFO}" | jq 'length')" -eq 0 ]] || [[ -z "$(echo "${USER_INFO}" | jq -r '.id // empty')" ]]; then
  CHECKS_WARNING+=("User Account: Test user ${TEST_USER} not found")
  [[ "${VERBOSE}" == "true" ]] && log_warn "  User not found: ${TEST_USER}"
else
  USER_DISPLAY_NAME=$(echo "${USER_INFO}" | jq -r '.displayName')
  USER_ID=$(echo "${USER_INFO}" | jq -r '.id')
  USER_UPN=$(echo "${USER_INFO}" | jq -r '.userPrincipalName')
  USER_ENABLED=$(echo "${USER_INFO}" | jq -r '.accountEnabled')

  CHECKS_PASSED+=("User Account: ${USER_DISPLAY_NAME} exists (${USER_UPN})")

  if [[ "${USER_ENABLED}" == "true" ]]; then
    CHECKS_PASSED+=("User Account: ${USER_DISPLAY_NAME} is enabled")
  elif [[ "${USER_ENABLED}" == "false" ]]; then
    CHECKS_FAILED+=("User Account: ${USER_DISPLAY_NAME} is disabled")
    FIXES_AVAILABLE+=("Enable user account: az ad user update --id ${USER_ID} --account-enabled true")
  else
    CHECKS_WARNING+=("User Account: Could not determine enabled status")
  fi

  [[ "${VERBOSE}" == "true" ]] && log_info "  Display Name: ${USER_DISPLAY_NAME}"
  [[ "${VERBOSE}" == "true" ]] && log_info "  UPN: ${USER_UPN}"
  [[ "${VERBOSE}" == "true" ]] && log_info "  User ID: ${USER_ID}"
  [[ "${VERBOSE}" == "true" ]] && log_info "  Enabled: ${USER_ENABLED}"
fi

# ============================================================================
# CHECK 4: CONFIGURATION CONSISTENCY
# ============================================================================
log_check "Checking Configuration Consistency..."

if [[ -n "${SWA_HOSTNAME}" ]] && [[ -n "${SPA_URIS}" ]]; then
  if echo "${SPA_URIS}" | grep -q "${SWA_HOSTNAME}"; then
    CHECKS_PASSED+=("Consistency: App redirect URI matches SWA hostname")
  else
    CHECKS_FAILED+=("Consistency: App redirect URI does not match SWA hostname")
    FIXES_AVAILABLE+=("Update redirect URI to match SWA hostname: ${SWA_HOSTNAME}")
  fi
fi

# Only check Function App if both name and resource group are provided
if [[ -n "${FUNCTION_APP_NAME}" ]] && [[ -n "${FUNCTION_APP_RG}" ]]; then
  FUNCTION_APP_AUTH=$(az functionapp config appsettings list --name "${FUNCTION_APP_NAME}" --resource-group "${FUNCTION_APP_RG}" --query "[?name=='AUTH_METHOD'].value" -o tsv 2>/dev/null || echo "")
  if [[ -n "${FUNCTION_APP_AUTH}" ]]; then
    if [[ "${FUNCTION_APP_AUTH}" == "azure_swa" ]]; then
      CHECKS_PASSED+=("Function App AUTH_METHOD is azure_swa")
    else
      CHECKS_FAILED+=("Function App AUTH_METHOD is ${FUNCTION_APP_AUTH} (expected azure_swa)")
      FIXES_AVAILABLE+=("Set Function App AUTH_METHOD=azure_swa to trust SWA headers")
    fi
  else
    CHECKS_WARNING+=("Unable to determine Function App AUTH_METHOD")
  fi
fi

if [[ -n "${APP_ID}" ]] && [[ -n "${CLIENT_ID_SET}" ]]; then
  SWA_APP_ID=$(echo "${APP_SETTINGS}" | jq -r '.AZURE_CLIENT_ID // empty')
  if [[ "${SWA_APP_ID}" == "${APP_ID}" ]]; then
    CHECKS_PASSED+=("Consistency: SWA AZURE_CLIENT_ID matches app ID")
  else
    CHECKS_FAILED+=("Consistency: SWA AZURE_CLIENT_ID does not match app ID")
    FIXES_AVAILABLE+=("Update SWA AZURE_CLIENT_ID to: ${APP_ID}")
  fi
fi

# ============================================================================
# CHECK 5: SWA CONFIGURATION FILE
# ============================================================================
log_check "Checking SWA Configuration File..."

CONFIG_FILE="${SCRIPT_DIR}/staticwebapp-entraid.config.json"
GENERATED_CONFIG="${SCRIPT_DIR}/generated/staticwebapp-entraid.${SWA_NAME}.staticwebapp.config.json"
CONFIG_SOURCE="${CONFIG_FILE}"

if [[ -f "${GENERATED_CONFIG}" ]]; then
  CONFIG_SOURCE="${GENERATED_CONFIG}"
fi

if [[ -f "${CONFIG_SOURCE}" ]]; then
  CHECKS_PASSED+=("SWA config file exists: $(basename "${CONFIG_SOURCE}")")

  # Check if routes are properly configured
  HAS_AUTH_ROUTE=$(jq -e '.routes[] | select(.route == "/.auth/*")' "${CONFIG_SOURCE}" 2>/dev/null || echo "")
  if [[ -n "${HAS_AUTH_ROUTE}" ]]; then
    CHECKS_PASSED+=("SWA config: /.auth/* route is accessible (prevents redirect loop)")
  else
    CHECKS_FAILED+=("SWA config: /.auth/* route not found (may cause redirect loop)")
    FIXES_AVAILABLE+=("Add /.auth/* route to staticwebapp-entraid.config.json")
  fi

  # Check if tenant ID is replaced
  ISSUER=$(jq -r '.auth.identityProviders.azureActiveDirectory.registration.openIdIssuer // ""' "${CONFIG_SOURCE}")
  if [[ "${ISSUER}" == *"AZURE_TENANT_ID"* ]]; then
    if [[ "${CONFIG_SOURCE}" == "${GENERATED_CONFIG}" ]]; then
      CHECKS_FAILED+=("Generated SWA config still contains AZURE_TENANT_ID placeholder")
      FIXES_AVAILABLE+=("Redeploy frontend with VITE_AUTH_ENABLED=true to refresh generated config")
    else
      CHECKS_WARNING+=("Template SWA config contains AZURE_TENANT_ID placeholder (expected when generated snapshot missing)")
      FIXES_AVAILABLE+=("Run 20-deploy-frontend.sh with VITE_AUTH_ENABLED=true to capture generated config")
    fi
  elif [[ -n "${ISSUER}" ]]; then
    CHECKS_PASSED+=("SWA config: openIdIssuer is configured with tenant ID")
    [[ "${VERBOSE}" == "true" ]] && log_info "  Issuer: ${ISSUER}"
  else
    CHECKS_FAILED+=("SWA config: openIdIssuer not configured")
    FIXES_AVAILABLE+=("Configure openIdIssuer in staticwebapp-entraid.config.json")
  fi
else
  CHECKS_WARNING+=("SWA config file not found: ${CONFIG_FILE}")
fi

# ============================================================================
# CHECK 6: ADDITIONAL VERIFICATION NOTES
# ============================================================================
log_check "Additional Configuration Notes..."

if [[ -n "${SWA_URL}" ]]; then
  CHECKS_PASSED+=("SWA URL is accessible: ${SWA_URL}")
  [[ "${VERBOSE}" == "true" ]] && log_info "  Frontend is deployed at: ${SWA_URL}"
  [[ "${VERBOSE}" == "true" ]] && log_info "  If sign-in fails, check browser Developer Tools (F12) for errors"
fi

# ============================================================================
# GENERATE OUTPUT
# ============================================================================

print_summary() {
  local passed=0
  local failed=0
  local warnings=0

  # Count array elements safely
  [[ -v CHECKS_PASSED[@] ]] && passed=${#CHECKS_PASSED[@]}
  [[ -v CHECKS_FAILED[@] ]] && failed=${#CHECKS_FAILED[@]}
  [[ -v CHECKS_WARNING[@] ]] && warnings=${#CHECKS_WARNING[@]}

  echo ""
  echo "========================================="
  echo "Entra ID Setup Verification Results"
  echo "========================================="
  echo ""

  if [[ ${passed} -gt 0 ]]; then
    echo -e "${GREEN}${PASS} Checks Passed (${passed})${NC}"
    if [[ -v CHECKS_PASSED[@] ]]; then
      for check in "${CHECKS_PASSED[@]}"; do
        echo "  - ${check}"
      done
    fi
    echo ""
  fi

  if [[ ${warnings} -gt 0 ]]; then
    echo -e "${YELLOW}${WARN} Warnings (${warnings})${NC}"
    if [[ -v CHECKS_WARNING[@] ]]; then
      for check in "${CHECKS_WARNING[@]}"; do
        echo "  - ${check}"
      done
    fi
    echo ""
  fi

  if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}${FAIL} Critical Issues (${failed})${NC}"
    if [[ -v CHECKS_FAILED[@] ]]; then
      for check in "${CHECKS_FAILED[@]}"; do
        echo "  - ${check}"
      done
    fi
    echo ""
  fi

  echo "========================================="
  echo "Summary: ${passed} passed, ${warnings} warnings, ${failed} failed"
  echo "========================================="
  echo ""

  if [[ ${failed} -gt 0 ]]; then
    exit 1
  elif [[ ${warnings} -gt 0 ]]; then
    exit 2
  else
    exit 0
  fi
}

if [[ "${SUGGEST_FIXES}" == "true" ]] && [[ -v FIXES_AVAILABLE[@] ]] && [[ ${#FIXES_AVAILABLE[@]} -gt 0 ]]; then
  echo ""
  echo "========================================="
  echo "Available Fixes"
  echo "========================================="
  echo ""

  for i in "${!FIXES_AVAILABLE[@]}"; do
    echo "$((i+1)). ${FIXES_AVAILABLE[$i]}"
  done
  echo ""

  if [[ "${AUTO_FIX}" == "true" ]]; then
    log_step "Applying fixes..."
    # Implement auto-fixes here
    log_warn "Auto-fix not yet implemented. Use Azure Portal or provide the CLI commands manually."
  fi
fi

print_summary
