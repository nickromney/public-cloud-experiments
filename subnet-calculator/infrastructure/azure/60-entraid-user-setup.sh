#!/usr/bin/env bash
#
# 60-entraid-user-setup.sh - Entra ID App Registration and User Setup
#
# This script configures and troubleshoots Entra ID app registration for SWA OAuth.
# It handles:
#   - Creating/updating app registration with correct redirect URIs
#   - Setting up redirect URIs in the correct place (web vs spa vs public client)
#   - Creating and managing client secrets
#   - Granting admin consent
#   - Testing user access
#   - Diagnosing authentication issues
#
# Usage:
#   # Interactive setup (recommended first time)
#   ./60-entraid-user-setup.sh
#
#   # Create new app registration
#   ./60-entraid-user-setup.sh --create --app-name "Subnet Calc" --swa-hostname "proud-bay-05b7e1c03.1.azurestaticapps.net"
#
#   # Fix redirect URIs on existing app
#   ./60-entraid-user-setup.sh --fix-redirects --app-id <client-id> --swa-hostname <hostname>
#
#   # Create new client secret
#   ./60-entraid-user-setup.sh --new-secret --app-id <client-id>
#
#   # Grant admin consent
#   ./60-entraid-user-setup.sh --admin-consent --app-id <client-id>
#
#   # Diagnose issues
#   ./60-entraid-user-setup.sh --diagnose --app-id <client-id> --swa-name <name>
#
# Options:
#   --create                  Create new app registration
#   --app-name <name>        Display name for app registration
#   --swa-hostname <host>    SWA hostname (proud-bay-05b7e1c03.1.azurestaticapps.net)
#   --fix-redirects          Fix redirect URIs on existing app
#   --new-secret             Create new client secret
#   --app-id <id>            Entra ID app registration client ID (auto-detect from SWA)
#   --swa-name <name>        Static Web App name (auto-detect)
#   --swa-hostname <host>    SWA hostname (auto-detect from SWA)
#   --admin-consent          Grant admin consent for permissions
#   --diagnose               Run diagnostic checks
#   --verbose                Show detailed output
#   --dry-run                Show what would be done without making changes

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
log_debug() { if [[ "${VERBOSE}" == "true" ]]; then echo -e "${BLUE}[DEBUG]${NC} $*"; fi; }

# Parse arguments
COMMAND="interactive"
APP_NAME=""
APP_ID=""
SWA_NAME=""
SWA_HOSTNAME=""
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --create) COMMAND="create"; shift ;;
    --app-name) APP_NAME="$2"; shift 2 ;;
    --fix-redirects) COMMAND="fix-redirects"; shift ;;
    --new-secret) COMMAND="new-secret"; shift ;;
    --app-id) APP_ID="$2"; shift 2 ;;
    --swa-name) SWA_NAME="$2"; shift 2 ;;
    --swa-hostname) SWA_HOSTNAME="$2"; shift 2 ;;
    --admin-consent) COMMAND="admin-consent"; shift ;;
    --diagnose) COMMAND="diagnose"; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

TENANT_ID=$(az account show --query tenantId -o tsv)
log_info "Tenant ID: ${TENANT_ID}"

# ============================================================================
# FUNCTION: Get SWA details
# ============================================================================
get_swa_details() {
  local rg="${1:-}"

  if [[ -z "${rg}" ]]; then
    local rg_count
    rg_count=$(az group list --query "length(@)" -o tsv)

    if [[ "${rg_count}" -eq 1 ]]; then
      rg=$(az group list --query "[0].name" -o tsv)
    fi
  fi

  if [[ -z "${SWA_NAME}" ]]; then
    if [[ -n "${rg}" ]]; then
      local swa_count
      swa_count=$(az staticwebapp list --resource-group "${rg}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

      if [[ "${swa_count}" -eq 1 ]]; then
        SWA_NAME=$(az staticwebapp list --resource-group "${rg}" --query "[0].name" -o tsv)
      fi
    fi
  fi

  if [[ -z "${SWA_HOSTNAME}" ]] && [[ -n "${SWA_NAME}" ]] && [[ -n "${rg}" ]]; then
    SWA_HOSTNAME=$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${rg}" --query defaultHostname -o tsv)
  fi
}

# ============================================================================
# FUNCTION: Get app ID from SWA settings
# ============================================================================
get_app_id_from_swa() {
  local swa="${1}"
  local rg="${2}"

  APP_ID=$(az staticwebapp appsettings list --name "${swa}" --resource-group "${rg}" \
    --query "properties.AZURE_CLIENT_ID" -o tsv 2>/dev/null || echo "")
}

# ============================================================================
# FUNCTION: Build app configuration JSON with reusable defaults
# ============================================================================
# Builds the JSON body for app registration configuration
# Usage: build_app_config [implicit_grants] [token_version] [add_user_read_permission]
# Returns JSON suitable for az rest --body
build_app_config() {
  local implicit_grants="${1:-true}"
  local token_version="${2:-2}"
  local add_user_read_permission="${3:-false}"

  local id_token="false"
  local access_token="false"

  if [[ "${implicit_grants}" == "true" ]]; then
    id_token="true"
    access_token="true"
  fi

  local config="{
    \"web\": {
      \"implicitGrantSettings\": {
        \"enableAccessTokenIssuance\": ${access_token},
        \"enableIdTokenIssuance\": ${id_token}
      }
    },
    \"api\": {
      \"requestedAccessTokenVersion\": ${token_version}
    }"

  if [[ "${add_user_read_permission}" == "true" ]]; then
    config="${config},\"requiredResourceAccess\": [
      {
        \"resourceAppId\": \"00000003-0000-0000-c000-000000000000\",
        \"resourceAccess\": [
          {
            \"id\": \"e1fe6dd8-ba31-4d61-89e7-88639da4683d\",
            \"type\": \"Scope\"
          }
        ]
      }
    ]"
  fi

  config="${config}}"

  echo "${config}"
}

# ============================================================================
# COMMAND: Interactive Setup
# ============================================================================
cmd_interactive() {
  log_step "Entra ID App Registration Setup"
  echo ""

  get_swa_details

  if [[ -n "${SWA_NAME}" ]]; then
    log_info "Found SWA: ${SWA_NAME}"
    log_info "Hostname: ${SWA_HOSTNAME}"

    get_app_id_from_swa "${SWA_NAME}" "$(az group list --query "[0].name" -o tsv)"

    if [[ -n "${APP_ID}" ]]; then
      log_info "Found app registration: ${APP_ID}"
      echo ""
      read -r -p "What would you like to do? (1=Create new, 2=Fix redirects, 3=New secret, 4=Admin consent, 5=Diagnose, 6=Exit): " choice

      case "${choice}" in
        1) COMMAND="create"; APP_NAME="Subnet Calculator Entra ID" ;;
        2) COMMAND="fix-redirects" ;;
        3) COMMAND="new-secret" ;;
        4) COMMAND="admin-consent" ;;
        5) COMMAND="diagnose" ;;
        6) exit 0 ;;
        *) log_error "Invalid choice"; exit 1 ;;
      esac
    else
      log_warn "No app registration found in SWA settings"
      log_info "Create a new one?"
      read -r -p "Enter app name (or press Enter to skip): " APP_NAME
      if [[ -n "${APP_NAME}" ]]; then
        COMMAND="create"
      else
        exit 0
      fi
    fi
  fi

  # Execute chosen command
  case "${COMMAND}" in
    create) cmd_create ;;
    fix-redirects) cmd_fix_redirects ;;
    new-secret) cmd_new_secret ;;
    admin-consent) cmd_admin_consent ;;
    diagnose) cmd_diagnose ;;
    *) log_error "No command selected"; exit 1 ;;
  esac
}

# ============================================================================
# COMMAND: Create new app registration
# ============================================================================
cmd_create() {
  log_step "Creating new app registration"

  # Auto-detect SWA details if not provided
  if [[ -z "${SWA_NAME}" ]]; then
    get_swa_details "$(az group list --query "[0].name" -o tsv 2>/dev/null || echo "")"
  fi

  if [[ -z "${APP_NAME}" ]]; then
    read -r -p "App name: " APP_NAME
  fi

  if [[ -z "${SWA_HOSTNAME}" ]]; then
    if [[ -n "${SWA_HOSTNAME}" ]]; then
      log_info "Using auto-detected SWA hostname: ${SWA_HOSTNAME}"
    else
      read -r -p "SWA hostname (e.g., proud-bay-05b7e1c03.1.azurestaticapps.net): " SWA_HOSTNAME
    fi
  fi

  local redirect_uri="https://${SWA_HOSTNAME}/.auth/login/aad/callback"

  log_info "Creating app: ${APP_NAME}"
  log_info "Redirect URI: ${redirect_uri}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "[DRY RUN] Would create app registration"
    return
  fi

  # Create app
  local app_output
  app_output=$(az ad app create --display-name "${APP_NAME}" --web-redirect-uris "${redirect_uri}" -o json)

  APP_ID=$(echo "${app_output}" | jq -r '.appId')
  local app_obj_id
  app_obj_id=$(echo "${app_output}" | jq -r '.id')

  log_success "App created: ${APP_ID}"

  # Create client secret
  log_info "Creating client secret..."
  local secret_output
  secret_output=$(az ad app credential reset --id "${APP_ID}" --display-name "swa-auth" -o json)

  local secret_value
  secret_value=$(echo "${secret_output}" | jq -r '.password')

  log_success "Secret created"
  echo ""
  log_info "========================================="
  log_info "SAVE THESE VALUES:"
  log_info "========================================="
  log_info "CLIENT_ID: ${APP_ID}"
  log_info "CLIENT_SECRET: ${secret_value}"
  log_info "TENANT_ID: ${TENANT_ID}"
  log_info "========================================="
  echo ""

  # Set implicit grant, token version, and API permissions
  log_info "Configuring implicit grant settings, token version, and API permissions..."
  local config
  config=$(build_app_config true 2 true)

  az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/${app_obj_id}" \
    --headers 'Content-Type=application/json' \
    --body "${config}" \
    --output none

  log_success "Implicit grant enabled, token version set to 2, and User.Read permission added"

  # Update SWA if found
  if [[ -n "${SWA_NAME}" ]]; then
    local rg
    rg=$(az staticwebapp show --name "${SWA_NAME}" --query resourceGroup -o tsv 2>/dev/null || az group list --query "[0].name" -o tsv)

    log_info "Updating SWA app settings..."
    az staticwebapp appsettings set \
      --resource-group "${rg}" \
      --name "${SWA_NAME}" \
      --setting-names \
        AZURE_CLIENT_ID="${APP_ID}" \
        AZURE_CLIENT_SECRET="${secret_value}" \
      --output none

    log_success "SWA updated with new credentials"
    log_info "  AZURE_CLIENT_ID=${APP_ID}"
  else
    log_warn "SWA not found. Update manually with:"
    log_info "  az staticwebapp appsettings set --resource-group <RG> --name <SWA-NAME> --setting-names AZURE_CLIENT_ID=${APP_ID} AZURE_CLIENT_SECRET=${secret_value}"
  fi
}

# ============================================================================
# COMMAND: Fix redirect URIs
# ============================================================================
cmd_fix_redirects() {
  log_step "Fixing redirect URIs"

  if [[ -z "${APP_ID}" ]]; then
    log_error "APP_ID not provided"
    exit 1
  fi

  if [[ -z "${SWA_HOSTNAME}" ]]; then
    read -r -p "SWA hostname: " SWA_HOSTNAME
  fi

  local redirect_uri="https://${SWA_HOSTNAME}/.auth/login/aad/callback"
  local app_obj_id
  app_obj_id=$(az ad app show --id "${APP_ID}" --query 'id' -o tsv)

  log_info "Setting redirect URIs correctly..."
  log_info "  Web (for SWA form_post): ${redirect_uri}"
  log_info "  Public client: (clearing)"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "[DRY RUN] Would update redirect URIs"
    return
  fi

  az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/${app_obj_id}" \
    --headers 'Content-Type=application/json' \
    --body "{
      \"web\": {
        \"redirectUris\": [\"${redirect_uri}\"],
        \"implicitGrantSettings\": {
          \"enableAccessTokenIssuance\": true,
          \"enableIdTokenIssuance\": true
        }
      },
      \"publicClient\": {
        \"redirectUris\": []
      }
    }" \
    --output none

  log_success "Redirect URIs fixed"
}

# ============================================================================
# COMMAND: Create new client secret
# ============================================================================
cmd_new_secret() {
  log_step "Creating new client secret"

  if [[ -z "${APP_ID}" ]]; then
    log_error "APP_ID not provided"
    exit 1
  fi

  log_warn "This will create a new secret. The old secret will stop working."
  read -r -p "Continue? (y/n): " confirm
  [[ "${confirm}" != "y" ]] && exit 0

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "[DRY RUN] Would create secret"
    return
  fi

  local secret_output
  secret_output=$(az ad app credential reset --id "${APP_ID}" --display-name "swa-auth-$(date +%s)" -o json)

  local secret_value
  secret_value=$(echo "${secret_output}" | jq -r '.password')
  local expires
  expires=$(echo "${secret_output}" | jq -r '.endDate')

  log_success "Secret created (expires: ${expires})"
  echo ""
  log_info "========================================="
  log_info "NEW SECRET:"
  log_info "========================================="
  log_info "${secret_value}"
  log_info "========================================="
  echo ""
  log_info "Update SWA app settings:"
  log_info "  AZURE_CLIENT_SECRET=${secret_value}"
}

# ============================================================================
# COMMAND: Grant admin consent
# ============================================================================
cmd_admin_consent() {
  log_step "Granting admin consent"

  if [[ -z "${APP_ID}" ]]; then
    log_error "APP_ID not provided"
    exit 1
  fi

  local consent_url="https://login.microsoftonline.com/${TENANT_ID}/adminconsent?client_id=${APP_ID}"

  log_info "Open this URL in a browser to grant admin consent:"
  log_info "${consent_url}"
  echo ""
  log_warn "You need to be an admin to grant consent"
}

# ============================================================================
# COMMAND: Diagnose issues
# ============================================================================
cmd_diagnose() {
  log_step "Running diagnostic checks"

  if [[ -z "${APP_ID}" ]]; then
    log_error "APP_ID not provided"
    exit 1
  fi

  local app_info
  app_info=$(az ad app show --id "${APP_ID}" -o json)

  echo ""
  log_info "App Registration Check:"
  log_info "  Display Name: $(echo "${app_info}" | jq -r '.displayName')"
  log_info "  App ID: $(echo "${app_info}" | jq -r '.appId')"

  # Check redirect URIs
  local web_uris spa_uris public_uris
  web_uris=$(echo "${app_info}" | jq -r '.web.redirectUris[]? // empty' | paste -sd ',' -)
  spa_uris=$(echo "${app_info}" | jq -r '.spa.redirectUris[]? // empty' | paste -sd ',' -)
  public_uris=$(echo "${app_info}" | jq -r '.publicClient.redirectUris[]? // empty' | paste -sd ',' -)

  echo ""
  log_info "Redirect URIs:"
  if [[ -n "${web_uris}" ]]; then
    log_info "  ✓ Web: ${web_uris}"
  else
    log_warn "  ✗ Web: (none)"
  fi

  if [[ -n "${spa_uris}" ]]; then
    log_info "  • SPA: ${spa_uris}"
  else
    log_info "  • SPA: (none)"
  fi

  if [[ -n "${public_uris}" ]]; then
    log_warn "  ✗ Public Client: ${public_uris} (should be empty for web apps)"
  else
    log_info "  ✓ Public Client: (empty)"
  fi

  # Check implicit grant
  local id_token_implicit access_token_implicit
  id_token_implicit=$(echo "${app_info}" | jq -r '.web.implicitGrantSettings.enableIdTokenIssuance // false')
  access_token_implicit=$(echo "${app_info}" | jq -r '.web.implicitGrantSettings.enableAccessTokenIssuance // false')

  echo ""
  log_info "Implicit Grant Settings:"
  if [[ "${id_token_implicit}" == "true" ]]; then log_info "  ID Token Issuance: enabled"; else log_warn "  ID Token Issuance: disabled"; fi
  if [[ "${access_token_implicit}" == "true" ]]; then log_info "  Access Token Issuance: enabled"; else log_warn "  Access Token Issuance: disabled"; fi

  # Check token version
  local token_version
  token_version=$(echo "${app_info}" | jq -r '.api.requestedAccessTokenVersion // "null"')

  echo ""
  log_info "Token Configuration:"
  if [[ "${token_version}" == "2" ]]; then log_info "  Token Version: 2"; else log_warn "  Token Version: ${token_version} (should be 2)"; fi

  # Check sign-in audience
  local sign_in_audience
  sign_in_audience=$(echo "${app_info}" | jq -r '.signInAudience // "unknown"')

  echo ""
  log_info "Sign-In Configuration:"
  if [[ "${sign_in_audience}" == "AzureADMyOrg" ]]; then log_info "  Sign-in Audience: Single-tenant (AzureADMyOrg)"; else log_warn "  Sign-in Audience: ${sign_in_audience}"; fi

  # Check app roles and permissions
  local app_roles req_resource_access
  app_roles=$(echo "${app_info}" | jq '.appRoles // [] | length')
  req_resource_access=$(echo "${app_info}" | jq '.requiredResourceAccess // [] | length')

  echo ""
  log_info "Permissions Configuration:"
  log_info "  App Roles: ${app_roles}"
  log_info "  Required Resource Access: ${req_resource_access}"

  # Verbose - show full JSON if requested
  if [[ "${VERBOSE}" == "true" ]]; then
    echo ""
    log_debug "Full app registration JSON:"
    echo "${app_info}" | jq '.' 2>&1 | sed 's/^/    /'
  fi

  # Summary
  echo ""
  if [[ -n "${web_uris}" ]] && [[ -z "${public_uris}" ]] && [[ "${id_token_implicit}" == "true" ]] && [[ "${token_version}" == "2" ]]; then
    log_success "Configuration looks correct!"

    echo ""
    log_info "If login still fails, check:"
    log_info "  1. Browser cache cleared for azurestaticapps.net"
    log_info "  2. Admin consent granted: ./60-entraid-user-setup.sh --admin-consent --app-id ${APP_ID}"
    log_info "  3. User account enabled in Entra ID"
    log_info "  4. SWA app settings updated with correct credentials"
    log_info ""
    log_info "To debug further, run with --verbose:"
    log_info "  ./60-entraid-user-setup.sh --diagnose --app-id ${APP_ID} --verbose"
  else
    log_warn "Issues found - run with --fix-redirects or --admin-consent to resolve"
  fi
}

# ============================================================================
# Main execution
# ============================================================================

echo ""
log_info "========================================="
log_info "Entra ID App Registration Setup"
log_info "========================================="
echo ""

case "${COMMAND}" in
  interactive) cmd_interactive ;;
  create) cmd_create ;;
  fix-redirects) cmd_fix_redirects ;;
  new-secret) cmd_new_secret ;;
  admin-consent) cmd_admin_consent ;;
  diagnose) cmd_diagnose ;;
  *) log_error "Unknown command: ${COMMAND}"; exit 1 ;;
esac

echo ""
log_success "Done!"
