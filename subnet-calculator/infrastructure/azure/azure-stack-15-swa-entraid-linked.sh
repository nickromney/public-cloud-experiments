#!/usr/bin/env bash
#
# azure-stack-15-swa-entraid-linked.sh - Deploy Stack 2: Public SWA + Entra ID + Linked Backend
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ User → Entra ID Login               │
#   └──────────────┬──────────────────────┘
#                  │
#   ┌──────────────▼──────────────────────┐
#   │ Azure Static Web App (Standard)     │
#   │ - TypeScript Vite SPA               │
#   │ - Entra ID authentication           │
#   │ - /api/* → SWA Proxy → Function     │
#   │ - Custom domain + azurestaticapps   │
#   └──────────────┬──────────────────────┘
#                  │ Linked backend
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Linked to SWA as managed backend  │
#   │ - Accessible via both custom domains│
#   │ - No auth on Function (SWA handles) │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (linked to SWA, no Function-level auth)
#   - Authentication: Entra ID on SWA (protects frontend + API via proxy)
#   - Security: Platform-level auth, HttpOnly cookies
#   - Use case: Enterprise apps, internal tools, RECOMMENDED setup
#   - Cost: ~$9/month (Standard tier SWA + Consumption)
#
# Key Benefits:
#   - Same-origin API calls (no CORS issues)
#   - HttpOnly cookies (secure, XSS protection)
#   - API accessed via SWA proxy (Entra ID required)
#   - Multiple redirect URIs (azurestaticapps.net + custom domain)
#   - Simple setup, good balance
#
# Custom Domains:
#   - SWA: static-swa-entraid-linked.publiccloudexperiments.net
#   - Function: subnet-calc-fa-entraid-linked.publiccloudexperiments.net
#
# Redirect URIs (both required):
#   - https://<app>.azurestaticapps.net/.auth/login/aad/callback
#   - https://static-swa-entraid-linked.publiccloudexperiments.net/.auth/login/aad/callback
#
# Usage:
#   # Run without credentials - script will offer to create app registration
#   ./azure-stack-15-swa-entraid-linked.sh
#
#   # Or run with existing credentials
#   AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="xxx" ./azure-stack-15-swa-entraid-linked.sh
#
# Environment variables (optional):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID (will prompt to create if not provided)
#   AZURE_CLIENT_SECRET  - Entra ID app registration secret (will prompt to create if not provided)
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   SWA_CUSTOM_DOMAIN    - SWA custom domain (default: static-swa-entraid-linked.publiccloudexperiments.net)
#   FUNC_CUSTOM_DOMAIN   - Function custom domain (default: subnet-calc-fa-entraid-linked.publiccloudexperiments.net)
#
# Note: If AZURE_CLIENT_ID/SECRET are not provided, the script will:
#   1. Check if an app registration exists
#   2. Offer to create one automatically using 60-entraid-user-setup.sh
#   3. Display the credentials for you to save and re-run the script
#
# Environment Variable Priority:
#   The script accepts credentials from multiple sources:
#   - Command-line: AZURE_CLIENT_ID=xxx ./script.sh (highest priority)
#   - .env file: Auto-loaded by direnv (if you've run 'direnv allow')
#   - Interactive: Script will offer to create if not found
#
#   To see what's set: The script will display credential sources at startup
#   To troubleshoot: Check if direnv is active with: echo $AZURE_CLIENT_ID

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

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
export PROJECT_ROOT

# Source utility functions
source "${SCRIPT_DIR}/lib/map-swa-region.sh"

# Configuration
readonly SWA_CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN:-static-swa-entraid-linked.publiccloudexperiments.net}"
readonly FUNC_CUSTOM_DOMAIN="${FUNC_CUSTOM_DOMAIN:-subnet-calc-fa-entraid-linked.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid-linked}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-entraid-linked}"
readonly STATIC_WEB_APP_SKU="Standard"  # Required for Entra ID

# Check if environment variables are provided, but don't require them yet
# (we'll offer to create the app registration if they're missing)
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"

# Map region to SWA-compatible region
REQUESTED_LOCATION="${LOCATION:-uksouth}"
SWA_LOCATION=$(map_swa_region "${REQUESTED_LOCATION}")
LOCATION="${REQUESTED_LOCATION}"  # Function App uses requested region (not readonly - will be temporarily overridden for SWA)
readonly SWA_LOCATION  # SWA uses mapped region

# Banner
echo ""
log_info "========================================="
log_info "Stack 2: Public SWA + Entra ID + Linked Backend"
log_info "RECOMMENDED SETUP"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID protected)"
log_info "  Backend:  Function App (linked, no Function auth)"
log_info "  Auth:     Entra ID on SWA (protects frontend + API)"
log_info "  Security: Platform-level, HttpOnly cookies"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption)"
log_info "  SWA Domain:  ${SWA_CUSTOM_DOMAIN}"
log_info "  Func Domain: ${FUNC_CUSTOM_DOMAIN}"
log_info "  Function Region: ${LOCATION}"
log_info "  SWA Region:      ${SWA_LOCATION}"
log_info ""
log_info "Key benefits:"
log_info "  ✓ Enterprise-grade authentication"
log_info "  ✓ Same-origin API calls (no CORS)"
log_info "  ✓ Secure HttpOnly cookies"
log_info "  ✓ Multiple domain support"
log_info ""

# Check prerequisites
log_step "Checking prerequisites..."
command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }
command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
command -v npm &>/dev/null || { log_error "npm not found"; exit 1; }
command -v uv &>/dev/null || { log_error "uv not found - install with: brew install uv"; exit 1; }

az account show &>/dev/null || { log_error "Not logged in to Azure"; exit 1; }
log_info "Prerequisites OK"
echo ""

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
export RESOURCE_GROUP
log_info "Using resource group: ${RESOURCE_GROUP}"
echo ""

# Check/Create Entra ID App Registration
log_step "Checking Entra ID app registration..."
echo ""

# Show where credentials are coming from (helps debug .env vs command-line)
if [[ -n "${AZURE_CLIENT_ID}" ]]; then
  log_info "AZURE_CLIENT_ID is set: ${AZURE_CLIENT_ID:0:8}... (source: .env or command-line)"
else
  log_info "AZURE_CLIENT_ID is not set"
fi

if [[ -n "${AZURE_CLIENT_SECRET}" ]]; then
  log_info "AZURE_CLIENT_SECRET is set: ****** (source: .env or command-line)"
else
  log_info "AZURE_CLIENT_SECRET is not set"
fi
echo ""

# Function to check if app registration exists and is valid
check_app_registration() {
  local app_id="$1"

  if [[ -z "${app_id}" ]]; then
    return 1
  fi

  if az ad app show --id "${app_id}" &>/dev/null; then
    log_info "Found existing app registration: ${app_id}"
    return 0
  else
    log_warn "App ID provided but app registration not found: ${app_id}"
    return 1
  fi
}

# Check if we have valid credentials
APP_EXISTS=false
if [[ -n "${AZURE_CLIENT_ID}" ]]; then
  if check_app_registration "${AZURE_CLIENT_ID}"; then
    APP_EXISTS=true
    log_info "App registration verified: ${AZURE_CLIENT_ID}"
  fi
fi

# If app doesn't exist or credentials not provided, offer to create
if [[ "${APP_EXISTS}" == "false" ]]; then
  echo ""
  log_warn "No valid Entra ID app registration found"
  log_info "This script can create one for you using 60-entraid-user-setup.sh"
  echo ""
  read -p "Create new Entra ID app registration? (Y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Creating Entra ID app registration..."
    echo ""

    # Get SWA hostname (we'll create it first if needed, or use existing)
    SWA_HOSTNAME=""
    if az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
      SWA_HOSTNAME=$(az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)
      log_info "Found existing SWA: ${SWA_HOSTNAME}"
    else
      # We'll need to create SWA first to get the hostname
      log_info "SWA doesn't exist yet. Creating it first to get hostname..."

      export STATIC_WEB_APP_NAME
      export STATIC_WEB_APP_SKU
      export LOCATION="${SWA_LOCATION}"  # Override with SWA-compatible region

      "${SCRIPT_DIR}/00-static-web-app.sh"

      SWA_HOSTNAME=$(az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query defaultHostname -o tsv)
      log_info "SWA created: ${SWA_HOSTNAME}"

      # Restore original location
      export LOCATION="${REQUESTED_LOCATION}"
    fi

    # Call the setup script to create app registration
    log_info "Calling 60-entraid-user-setup.sh..."
    "${SCRIPT_DIR}/60-entraid-user-setup.sh" \
      --create \
      --app-name "Subnet Calculator - ${STATIC_WEB_APP_NAME}" \
      --swa-hostname "${SWA_HOSTNAME}"

    echo ""
    log_warn "IMPORTANT: The script has created the app registration and displayed the credentials."
    log_warn "Please set these environment variables and re-run this script:"
    log_warn "  export AZURE_CLIENT_ID=<client-id>"
    log_warn "  export AZURE_CLIENT_SECRET=<client-secret>"
    log_warn ""
    log_warn "Or run with:"
    log_warn "  AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=yyy $0"
    exit 0
  else
    log_error "Entra ID app registration required. Please either:"
    log_error "  1. Run this script again and choose 'Y' to create one"
    log_error "  2. Create one manually with: ${SCRIPT_DIR}/60-entraid-user-setup.sh"
    log_error "  3. Provide existing credentials: AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=yyy $0"
    exit 1
  fi
fi

# Validate we have credentials now
if [[ -z "${AZURE_CLIENT_ID}" ]] || [[ -z "${AZURE_CLIENT_SECRET}" ]]; then
  log_error "AZURE_CLIENT_ID and AZURE_CLIENT_SECRET are required"
  log_error "Usage: AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=yyy $0"
  exit 1
fi

readonly AZURE_CLIENT_ID
readonly AZURE_CLIENT_SECRET
echo ""

# Step 1: Create Function App
log_step "Step 1/7: Creating Function App..."
echo ""

export FUNCTION_APP_NAME
export LOCATION

# Check if Function App was newly created or already existed
FUNCTION_APP_EXISTED=false
if az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  FUNCTION_APP_EXISTED=true
fi

"${SCRIPT_DIR}/10-function-app.sh"

log_info "Configuring Function App settings (no auth - SWA handles it)..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=none \
    CORS_ORIGINS="https://${SWA_CUSTOM_DOMAIN}" \
  --output none

log_info "Function App configured"
echo ""

# Step 2: Deploy Function API
log_step "Step 2/7: Deploying Function API..."
echo ""

# If Function App already existed, ask if user wants to redeploy
SKIP_DEPLOYMENT=false
if [[ "${FUNCTION_APP_EXISTED}" == "true" ]]; then
  log_info "Function App ${FUNCTION_APP_NAME} already exists."
  read -p "Redeploy Function App code? (Y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    SKIP_DEPLOYMENT=true
    log_info "Skipping deployment - using existing Function App code"
  fi
fi

if [[ "${SKIP_DEPLOYMENT}" == "false" ]]; then
  export DISABLE_AUTH=true  # No auth on Function (SWA handles it)

  "${SCRIPT_DIR}/22-deploy-function-zip.sh"

  log_info "Function App deployed"
  sleep 30
fi
echo ""

# Step 3: Create Static Web App (if not already created)
log_step "Step 3/7: Creating Azure Static Web App..."
echo ""

# Check if SWA already exists (might have been created during app registration)
if az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Static Web App already exists: ${STATIC_WEB_APP_NAME}"
else
  export STATIC_WEB_APP_NAME
  export STATIC_WEB_APP_SKU
  export LOCATION="${SWA_LOCATION}"  # Override with SWA-compatible region

  "${SCRIPT_DIR}/00-static-web-app.sh"

  # Restore original location for subsequent steps
  export LOCATION="${REQUESTED_LOCATION}"

  log_info "Static Web App created"
fi

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App URL: https://${SWA_URL}"
echo ""

# Step 4: Link Function App to SWA
log_step "Step 4/7: Linking Function App to SWA..."
echo ""

FUNC_RESOURCE_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info "Linking ${FUNCTION_APP_NAME} to ${STATIC_WEB_APP_NAME}..."
az staticwebapp backends link \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --backend-resource-id "${FUNC_RESOURCE_ID}" \
  --backend-region "${LOCATION}" \
  --output none

log_info "Function App linked to SWA"
echo ""

# Step 5: Update Entra ID App Registration
log_step "Step 5/7: Updating Entra ID app registration with redirect URIs..."
echo ""

log_info "Adding redirect URIs for both domains..."
log_info "  1. https://${SWA_URL}/.auth/login/aad/callback"
log_info "  2. https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"
echo ""

# Build redirect URIs list
NEW_URI_1="https://${SWA_URL}/.auth/login/aad/callback"
NEW_URI_2="https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"

# Get current URIs
REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris[]" -o tsv 2>/dev/null | cat)

# Check if both URIs are already present
NEEDS_UPDATE=false
if ! echo "${REDIRECT_URIS}" | grep -qF "${NEW_URI_1}"; then
  NEEDS_UPDATE=true
fi
if ! echo "${REDIRECT_URIS}" | grep -qF "${NEW_URI_2}"; then
  NEEDS_UPDATE=true
fi

if [[ "${NEEDS_UPDATE}" == "false" ]]; then
  log_info "Redirect URIs already configured correctly"
else
  # Add new URIs to list - use process substitution to avoid trailing newline issues
  mapfile -t URI_ARRAY < <(printf '%s\n%s\n%s\n' "${REDIRECT_URIS}" "${NEW_URI_1}" "${NEW_URI_2}" | grep -v '^$' | sort -u)

  # Ensure we have at least one URI
  if [ ${#URI_ARRAY[@]} -eq 0 ]; then
    log_error "No redirect URIs to configure"
    exit 1
  fi

  # Update redirect URIs
  log_info "Updating ${#URI_ARRAY[@]} redirect URI(s)..."

  # Call az directly with array expansion
  az ad app update \
    --id "${AZURE_CLIENT_ID}" \
    --web-redirect-uris "${URI_ARRAY[@]}" \
    --output none

  log_info "Redirect URIs updated"
fi

# Add logout URI (check if already set)
CURRENT_LOGOUT_URL=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.logoutUrl" -o tsv 2>/dev/null | cat)

TARGET_LOGOUT_URL="https://${SWA_CUSTOM_DOMAIN}/logged-out.html"

if [[ "${CURRENT_LOGOUT_URL}" == "${TARGET_LOGOUT_URL}" ]]; then
  log_info "Logout URL already configured correctly"
else
  log_info "Setting logout URL: ${TARGET_LOGOUT_URL}"
  az ad app update \
    --id "${AZURE_CLIENT_ID}" \
    --set web.logoutUrl="https://${SWA_CUSTOM_DOMAIN}/logged-out.html" \
    --output none
  log_info "Logout URL updated"
fi

log_info "Entra ID app configuration verified"
echo ""

# Step 6: Configure Entra ID on SWA
log_step "Step 6/7: Configuring Entra ID authentication on SWA..."
echo ""

export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export AZURE_CLIENT_SECRET

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
echo ""

# Step 7: Deploy Frontend
log_step "Step 7/7: Deploying frontend..."
echo ""

log_info "Building and deploying frontend with Entra ID auth..."
log_info "  API URL: (empty - use /api route via SWA proxy)"

export FRONTEND=typescript
export VITE_AUTH_ENABLED=true  # Entra ID via SWA built-in provider
export VITE_API_URL=""  # Use SWA proxy to linked backend
export STATIC_WEB_APP_NAME
export RESOURCE_GROUP

"${SCRIPT_DIR}/20-deploy-frontend.sh"

log_info "Frontend deployed"
echo ""

# Step 8: Configure Custom Domains
log_step "Step 8/7: Configuring custom domains..."
echo ""

log_info "SWA Custom domain: ${SWA_CUSTOM_DOMAIN}"
log_info ""
log_warn "MANUAL STEP REQUIRED:"
log_warn "Create DNS CNAME record:"
log_warn "  ${SWA_CUSTOM_DOMAIN} → ${SWA_URL}"
log_warn ""
read -r -p "Press Enter after DNS record is created..."

export CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN}"
"${SCRIPT_DIR}/41-configure-custom-domain-swa.sh"

log_info "SWA custom domain configured"
echo ""

FUNC_DEFAULT_HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.defaultHostName" -o tsv)

# Get custom domain verification ID for TXT record
VERIFICATION_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.customDomainVerificationId" -o tsv)

log_info "Function App Custom domain: ${FUNC_CUSTOM_DOMAIN}"
log_info ""
log_warn "MANUAL STEP REQUIRED:"
log_warn "Create TWO DNS records:"
log_warn ""
log_warn "1. CNAME record (for routing traffic):"
log_warn "   Name:  ${FUNC_CUSTOM_DOMAIN}"
log_warn "   Type:  CNAME"
log_warn "   Value: ${FUNC_DEFAULT_HOSTNAME}"
log_warn ""
log_warn "   IMPORTANT: If using Cloudflare, set to 'DNS only' (grey cloud)"
log_warn "   Azure CANNOT issue SSL certificates if Cloudflare proxy is enabled!"
log_warn "   The CNAME must point directly to Azure, not Cloudflare IPs."
log_warn ""
log_warn "2. TXT record (for domain ownership verification):"
log_warn "   Name:  asuid.${FUNC_CUSTOM_DOMAIN}"
log_warn "   Type:  TXT"
log_warn "   Value: ${VERIFICATION_ID}"
log_warn ""
read -r -p "Press Enter after BOTH DNS records are created..."

log_info "Adding custom domain to Function App..."
az functionapp config hostname add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${FUNC_CUSTOM_DOMAIN}" \
  --output none

log_info "Creating App Service Managed Certificate (free)..."
az functionapp config ssl create \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${FUNC_CUSTOM_DOMAIN}" \
  --output none

log_info "Waiting for certificate to be issued (this may take 30-60 seconds)..."
THUMBPRINT=""
MAX_ATTEMPTS=12
ATTEMPT=0

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))

  # Use az webapp (not functionapp) to check certificate status
  THUMBPRINT=$(az webapp config ssl show \
    --resource-group "${RESOURCE_GROUP}" \
    --certificate-name "${FUNC_CUSTOM_DOMAIN}" \
    --query thumbprint -o tsv 2>/dev/null || echo "")

  if [[ -n "${THUMBPRINT}" ]]; then
    log_info "✓ Certificate issued (thumbprint: ${THUMBPRINT})"
    break
  fi

  log_info "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: Certificate not ready yet, waiting 5 seconds..."
  sleep 5
done

if [[ -z "${THUMBPRINT}" ]]; then
  log_error "Certificate creation timed out after ${MAX_ATTEMPTS} attempts"
  log_error "The certificate may still be processing. Check Azure Portal or run:"
  log_error "  az webapp config ssl show -g ${RESOURCE_GROUP} --certificate-name ${FUNC_CUSTOM_DOMAIN}"
  log_error ""
  log_error "Once ready, bind it manually with:"
  log_error "  az functionapp config ssl bind --name ${FUNCTION_APP_NAME} -g ${RESOURCE_GROUP} \\"
  log_error "    --certificate-thumbprint <thumbprint> --ssl-type SNI"
else
  log_info "Binding SSL certificate..."
  az functionapp config ssl bind \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --certificate-thumbprint "${THUMBPRINT}" \
    --ssl-type SNI \
    --output none
  log_info "✓ HTTPS enabled with managed certificate"
fi

log_info "Function App custom domain configured"
echo ""

# Summary
log_info "========================================="
log_info "Stack 2 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA Primary:  https://${SWA_CUSTOM_DOMAIN}"
log_info "  SWA Default:  https://${SWA_URL}"
log_info "  Function:     https://${FUNC_CUSTOM_DOMAIN}"
log_info ""
log_info "Authentication:"
log_info "  Type:         Entra ID (platform-level)"
log_info "  Login URL:    https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad"
log_info "  Logout URL:   https://${SWA_CUSTOM_DOMAIN}/logout"
log_info "  User Info:    https://${SWA_CUSTOM_DOMAIN}/.auth/me"
log_info ""
log_info "Test the deployment:"
log_info "  1. Visit https://${SWA_CUSTOM_DOMAIN}"
log_info "  2. Sign in with Entra ID credentials"
log_info "  3. Verify API calls work via /api/* proxy"
log_info "  4. Test logout flow"
log_info ""
log_info "Redirect URIs configured:"
log_info "  - https://${SWA_URL}/.auth/login/aad/callback"
log_info "  - https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "API Documentation:"
log_info "  https://${FUNC_CUSTOM_DOMAIN}/api/v1/docs"
log_info ""
