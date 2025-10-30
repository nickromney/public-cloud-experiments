#!/usr/bin/env bash
#
# 52-setup-app-registration.sh - Setup Entra ID App Registration with Key Vault Secret Storage
#
# This script automates Entra ID app registration creation/detection and stores
# the client secret in Azure Key Vault using a naming convention tied to the SWA name.
#
# Usage:
# # Auto-create app registration
# STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
# CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" \
# ./52-setup-app-registration.sh
#
# # Use existing app registration
# AZURE_CLIENT_ID="existing-app-id" \
# STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint" \
# CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" \
# ./52-setup-app-registration.sh
#
# Input (environment variables required):
# STATIC_WEB_APP_NAME - SWA name (used for app name and secret name)
# CUSTOM_DOMAIN - Custom domain for redirect URI
# KEY_VAULT_NAME - Key Vault for secret storage
#
# Input (environment variables optional):
# AZURE_CLIENT_ID - Use existing app registration (skip creation)
# SWA_DEFAULT_HOSTNAME - Add azurestaticapps.net redirect URI (optional)
#
# Output (exported environment variables):
# AZURE_CLIENT_ID - App registration client ID
#
# Naming Convention:
# App Display Name: "Subnet Calculator - ${STATIC_WEB_APP_NAME}"
# Secret Name: "${STATIC_WEB_APP_NAME}-client-secret"
#
# Behavior:
# - If AZURE_CLIENT_ID provided: Validate app, ensure secret in Key Vault
# - If not provided: Search by display name, create if not found
# - If secret exists in Key Vault: Prompt to reuse or regenerate
#
# Exit Codes:
# 0 - Success (app registration ready, secret stored)
# 1 - Error (app not found, secret storage failed, Key Vault not accessible)

set -euo pipefail

# Colors and logging functions (skip if already defined by parent script)
if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  NC='\033[0m'

  log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
  log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
  log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
  log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
fi

# Validate required environment variables
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_error "STATIC_WEB_APP_NAME environment variable is required"
  exit 1
fi

if [[ -z "${CUSTOM_DOMAIN:-}" ]]; then
  log_error "CUSTOM_DOMAIN environment variable is required"
  exit 1
fi

if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
  log_error "KEY_VAULT_NAME environment variable is required"
  log_error "Run script 51 first to setup Key Vault"
  exit 1
fi

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_step "Setting up Entra ID app registration for ${STATIC_WEB_APP_NAME}..."

# Define naming convention
APP_DISPLAY_NAME="Subnet Calculator - ${STATIC_WEB_APP_NAME}"
SECRET_NAME="${STATIC_WEB_APP_NAME}-client-secret"

# Build redirect URIs
REDIRECT_URI_CUSTOM="https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
REDIRECT_URIS=("${REDIRECT_URI_CUSTOM}")

if [[ -n "${SWA_DEFAULT_HOSTNAME:-}" ]]; then
  REDIRECT_URI_DEFAULT="https://${SWA_DEFAULT_HOSTNAME}/.auth/login/aad/callback"
  REDIRECT_URIS+=("${REDIRECT_URI_DEFAULT}")
  log_info "Redirect URIs: Custom domain + azurestaticapps.net"
else
  log_info "Redirect URI: Custom domain only"
fi

# Check if app registration already exists
if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
  log_info "Using provided AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}"

  # Validate app exists
  if ! az ad app show --id "${AZURE_CLIENT_ID}" &>/dev/null; then
    log_error "App registration ${AZURE_CLIENT_ID} not found"
    exit 1
  fi

  APP_OBJECT_ID=$(az ad app show --id "${AZURE_CLIENT_ID}" --query id -o tsv)
  log_info "App registration found"

else
  log_info "Searching for app registration: ${APP_DISPLAY_NAME}"

  # Search by display name
  EXISTING_APP=$(az ad app list \
    --display-name "${APP_DISPLAY_NAME}" \
    --query "[0].{appId: appId, objectId: id}" -o json 2>/dev/null || echo "{}")

  AZURE_CLIENT_ID=$(echo "${EXISTING_APP}" | jq -r '.appId // empty')
  APP_OBJECT_ID=$(echo "${EXISTING_APP}" | jq -r '.objectId // empty')

  if [[ -n "${AZURE_CLIENT_ID}" ]]; then
    log_info "Found existing app registration: ${AZURE_CLIENT_ID}"
  else
    log_info "Creating new app registration: ${APP_DISPLAY_NAME}"

    # Build redirect URIs JSON array
    REDIRECT_URIS_JSON=$(printf '"%s",' "${REDIRECT_URIS[@]}" | sed 's/,$//')

    # Create app registration via Graph API
    CREATE_RESULT=$(az rest --method POST \
      --uri "https://graph.microsoft.com/v1.0/applications" \
      --headers 'Content-Type=application/json' \
      --body "{
        \"displayName\": \"${APP_DISPLAY_NAME}\",
        \"signInAudience\": \"AzureADMyOrg\",
        \"web\": {
          \"redirectUris\": [${REDIRECT_URIS_JSON}],
          \"implicitGrantSettings\": {
            \"enableAccessTokenIssuance\": true,
            \"enableIdTokenIssuance\": true
          }
        }
      }")

    AZURE_CLIENT_ID=$(echo "${CREATE_RESULT}" | jq -r '.appId')
    APP_OBJECT_ID=$(echo "${CREATE_RESULT}" | jq -r '.id')

    log_info "App registration created: ${AZURE_CLIENT_ID}"
  fi
fi

# Update redirect URIs (in case they changed)
log_info "Updating redirect URIs..."
REDIRECT_URIS_JSON=$(printf '"%s",' "${REDIRECT_URIS[@]}" | sed 's/,$//')

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
  --headers 'Content-Type=application/json' \
  --body "{
    \"web\": {
      \"redirectUris\": [${REDIRECT_URIS_JSON}],
      \"implicitGrantSettings\": {
        \"enableAccessTokenIssuance\": true,
        \"enableIdTokenIssuance\": true
      }
    }
  }" \
  --output none

log_info "Redirect URIs updated"

# Check if secret already exists in Key Vault
log_info "Checking for existing secret in Key Vault..."

EXISTING_SECRET=$(az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --query "{created: attributes.created, enabled: attributes.enabled}" -o json 2>/dev/null || echo "{}")

SECRET_EXISTS=$(echo "${EXISTING_SECRET}" | jq -r '.created // empty')

if [[ -n "${SECRET_EXISTS}" ]]; then
  log_warn "Secret '${SECRET_NAME}' already exists in Key Vault"
  echo "Created: ${SECRET_EXISTS}"
  echo ""
  echo "Options:"
  echo " 1. Reuse existing secret (recommended if working)"
  echo " 2. Regenerate new secret (creates new app credential)"
  echo ""
  read -p "Choice [1]: " -n 1 -r
  echo

  if [[ $REPLY =~ ^[2]$ ]]; then
    log_info "Regenerating secret..."
    REGENERATE_SECRET=true
  else
    log_info "Reusing existing secret"
    REGENERATE_SECRET=false
  fi
else
  log_info "No existing secret found. Generating new secret..."
  REGENERATE_SECRET=true
fi

if [[ "${REGENERATE_SECRET}" == "true" ]]; then
  # Generate new client secret
  log_info "Creating new client secret on app registration..."

  SECRET_DESCRIPTION="Generated by script 52 on $(date -u +%Y-%m-%d)"

  SECRET_RESULT=$(az ad app credential reset \
    --id "${AZURE_CLIENT_ID}" \
    --append \
    --display-name "${SECRET_DESCRIPTION}" \
    --query "password" -o tsv)

  if [[ -z "${SECRET_RESULT}" ]]; then
    log_error "Failed to create client secret"
    exit 1
  fi

  # Store in Key Vault
  log_info "Storing secret in Key Vault as: ${SECRET_NAME}"

  if ! az keyvault secret set \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${SECRET_NAME}" \
    --value "${SECRET_RESULT}" \
    --description "Client secret for ${APP_DISPLAY_NAME}" \
    --output none; then
    log_error "Failed to store secret in Key Vault"
    log_error "Secret was created on app registration but not stored"
    exit 1
  fi

  log_info "Secret stored successfully"
fi

# Export for caller
export AZURE_CLIENT_ID

log_info "App registration ready: ${AZURE_CLIENT_ID}"
log_info "Secret available in Key Vault as: ${SECRET_NAME}"
