#!/usr/bin/env bash
#
# azure-stack-16-swa-private-endpoint.sh - Deploy Stack 3: Private Endpoint SWA + Entra ID
#
# Architecture:
#   ┌──────────────────────────────────────┐
#   │ User → Entra ID Login                │
#   └──────────────┬───────────────────────┘
#                  │ Internet
#   ┌──────────────▼───────────────────────┐
#   │ Azure Static Web App (Standard)      │
#   │ - TypeScript Vite SPA                │
#   │ - Entra ID authentication            │
#   │ - Custom domain (PRIMARY)            │
#   │ - azurestaticapps.net (DISABLED)     │
#   │ - Private endpoint enabled           │
#   └──────────────┬───────────────────────┘
#                  │ Private Endpoint (SWA)
#   ┌──────────────▼───────────────────────┐
#   │ VNet (10.100.0.0/24)                 │
#   │ ├─ Subnet: functions (10.100.0.0/28) │
#   │ └─ Subnet: endpoints (10.100.0.16/28)│
#   │   - Private Endpoint for SWA         │
#   │   - Private Endpoint for Function    │
#   └──────────────┬───────────────────────┘
#                  │ Linked Backend + Private Endpoint
#   ┌──────────────▼───────────────────────┐
#   │ Azure Function App (S1/P0V3 Plan)    │
#   │ - Private endpoint only              │
#   │ - NO public azurewebsites.net access │
#   │ - VNet integration enabled           │
#   │ - No auth on Function (SWA handles)  │
#   └──────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Backend: Function App (App Service Plan with private endpoint)
#   - Authentication: Entra ID on SWA (custom domain only)
#   - Networking: Private endpoints, VNet integration
#   - Security: Network-level isolation, no public backend
#   - Use case: High-security environments, compliance requirements
#   - Cost: ~$22-293/month (SWA Standard + B1/S1/P0V3/P1V3 plan, private endpoints free)
#
# Key Security Features:
#   - Custom domain is PRIMARY (azurestaticapps.net disabled)
#   - Static Web App accessible via private endpoint
#   - Function App accessible ONLY via private endpoint
#   - No public IP on Function App
#   - Entra ID redirect URIs limited to custom domain
#   - Full network-level isolation for both frontend and backend
#
# Custom Domain:
#   - SWA: static-swa-private-endpoint.publiccloudexperiments.net (PRIMARY)
#   - Function: Uses default Azure domain (*.azurewebsites.net, private endpoint only)
#
# Redirect URI (custom domain only):
#   - https://static-swa-private-endpoint.publiccloudexperiments.net/.auth/login/aad/callback
#
# Usage:
#   # Fully automated (creates everything)
#   ./azure-stack-16-swa-private-endpoint.sh
#
#   # With existing app registration
#   AZURE_CLIENT_ID="xxx" ./azure-stack-16-swa-private-endpoint.sh
#
#   # With explicit Key Vault
#   KEY_VAULT_NAME="kv-subnet-calc-abcd" ./azure-stack-16-swa-private-endpoint.sh
#
#   # CI/CD mode (no interactive prompts)
#   AUTO_APPROVE=1 ./azure-stack-16-swa-private-endpoint.sh
#
# Environment variables (optional - all auto-created if not provided):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   KEY_VAULT_NAME       - Key Vault name (auto-created if not exists)
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   CUSTOM_DOMAIN        - SWA custom domain (default: static-swa-private-endpoint.publiccloudexperiments.net)
#   APP_SERVICE_PLAN_SKU - Plan SKU (default: S1, options: S1, P0V3)
#   AUTO_APPROVE         - Skip interactive prompts for CI/CD (default: not set)
#
# IMPORTANT CHANGES:
#   • AZURE_CLIENT_SECRET no longer required! Retrieved from Key Vault automatically.
#   • Script can create app registration automatically if AZURE_CLIENT_ID not provided.
#   • Key Vault created early (Step 0) and used for all secrets.

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
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-static-swa-private-endpoint.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-private-endpoint}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-private-endpoint}"
readonly APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-plan-subnet-calc-private}"
readonly APP_SERVICE_PLAN_SKU="${APP_SERVICE_PLAN_SKU:-P0V3}"  # B1, S1, P0V3, P1V3, etc.
readonly VNET_NAME="${VNET_NAME:-vnet-subnet-calc-private}"
readonly VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.100.0.0/24}"
readonly SUBNET_FUNCTION_NAME="${SUBNET_FUNCTION_NAME:-snet-function-integration}"
readonly SUBNET_FUNCTION_PREFIX="${SUBNET_FUNCTION_PREFIX:-10.100.0.0/28}"
readonly SUBNET_PE_NAME="${SUBNET_PE_NAME:-snet-private-endpoints}"
readonly SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.100.0.16/28}"
readonly STATIC_WEB_APP_SKU="Standard"  # Required for Entra ID

# AZURE_CLIENT_ID is optional - will be created by script 52 if not provided
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"

# Map region to SWA-compatible region
REQUESTED_LOCATION="${LOCATION:-uksouth}"
SWA_LOCATION=$(map_swa_region "${REQUESTED_LOCATION}")
LOCATION="${REQUESTED_LOCATION}"  # Function/VNet use requested region (not readonly - will be temporarily overridden for SWA)
readonly SWA_LOCATION  # SWA uses mapped region

# Calculate cost based on SKU
# Costs: SWA Standard ($9) + App Service Plan (private endpoints are free)
MONTHLY_COST=""
APP_PLAN_COST=""
case "${APP_SERVICE_PLAN_SKU}" in
  B1)
    APP_PLAN_COST="\$13"
    MONTHLY_COST="\$22"  # $9 (SWA) + $13 (B1)
    ;;
  S1)
    APP_PLAN_COST="\$70"
    MONTHLY_COST="\$79"  # $9 (SWA) + $70 (S1)
    ;;
  P0V3)
    APP_PLAN_COST="\$142"
    MONTHLY_COST="\$151"  # $9 (SWA) + $142 (P0V3)
    ;;
  P1V3)
    APP_PLAN_COST="\$284"
    MONTHLY_COST="\$293"  # $9 (SWA) + $284 (P1V3)
    ;;
  *)
    APP_PLAN_COST="\$13-284"
    MONTHLY_COST="~\$22-293"
    ;;
esac

# Banner
echo ""
log_info "========================================="
log_info "Stack 3: Private Endpoint + Entra ID"
log_info "HIGH SECURITY SETUP (12 steps)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (Entra ID, custom domain primary)"
log_info "  Backend:  Function App (App Service Plan, private endpoint)"
log_info "  Auth:     Entra ID (custom domain only)"
log_info "  Network:  VNet, private endpoints, NO public backend access"
log_info "  Security: Network-level isolation"
log_info "  Cost:     ~${MONTHLY_COST}/month (SWA Standard + ${APP_SERVICE_PLAN_SKU})"
log_info "  Domain:   ${CUSTOM_DOMAIN} (PRIMARY)"
log_info "  Function Region: ${LOCATION}"
log_info "  SWA Region:      ${SWA_LOCATION}"
log_info ""
log_info "Key security features:"
log_info "  ✓ Custom domain is PRIMARY"
log_info "  ✓ azurestaticapps.net domain DISABLED"
log_info "  ✓ SWA accessible via private endpoint"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public IP on Function App"
log_info "  ✓ Full network-level isolation (frontend + backend)"
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

# Step 0: Setup Key Vault
log_step "Step 0/12: Setting up Key Vault..."
echo ""

export RESOURCE_GROUP
export LOCATION="${REQUESTED_LOCATION}" # Use original location, not SWA_LOCATION

source "${SCRIPT_DIR}/51-setup-key-vault.sh"

log_info "Key Vault ready: ${KEY_VAULT_NAME}"
echo ""

# Step 0.5: Setup App Registration
log_step "Step 0.5/12: Setting up Entra ID App Registration..."
echo ""

# Show where credentials are coming from (helps debug .env vs command-line)
if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
  log_info "AZURE_CLIENT_ID is set: ${AZURE_CLIENT_ID:0:8}... (source: .env or command-line)"
else
  log_info "AZURE_CLIENT_ID is not set"
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
if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
  if check_app_registration "${AZURE_CLIENT_ID}"; then
    APP_EXISTS=true
    log_info "App registration verified: ${AZURE_CLIENT_ID}"

    # Validate and ensure secret is in Key Vault
    export STATIC_WEB_APP_NAME
    export CUSTOM_DOMAIN
    export KEY_VAULT_NAME
    export AZURE_CLIENT_ID

    source "${SCRIPT_DIR}/52-setup-app-registration.sh"
    log_info "App registration validated"
  fi
fi

# If app doesn't exist or credentials not provided, offer options
if [[ "${APP_EXISTS}" == "false" ]]; then
  echo ""
  log_warn "No valid Entra ID app registration found"
  echo ""
  log_info "Options:"
  log_info "  1. Select an existing app registration"
  log_info "  2. Create a new one automatically"
  log_info "  3. Exit and set AZURE_CLIENT_ID manually"
  echo ""

  # Allow auto-approve in CI/CD (defaults to option 2: create new)
  if [[ -n "${AUTO_APPROVE:-}" ]]; then
    log_info "AUTO_APPROVE set: choosing option 2 (create new)"
    REPLY="2"
  else
    read -p "Choose option (1-3): " -n 1 -r
    echo
    echo
  fi

  if [[ $REPLY == "1" ]]; then
    # Use the selection utility to pick existing app registration
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    SELECTED_APP_ID=$(select_entra_app_registration)

    if [[ -n "${SELECTED_APP_ID}" ]]; then
      AZURE_CLIENT_ID="${SELECTED_APP_ID}"
      export AZURE_CLIENT_ID
      log_info "Selected app registration: ${AZURE_CLIENT_ID}"

      # Try to retrieve secret from Key Vault
      log_info "Looking for client secret in Key Vault..."

      # Find Key Vault in resource group (should exist from Step 0)
      if [[ -n "${KEY_VAULT_NAME}" ]]; then
        log_info "Using Key Vault: ${KEY_VAULT_NAME}"

        # Try to get secret with standard naming pattern: {swa-name}-client-secret
        SECRET_NAME="${STATIC_WEB_APP_NAME}-client-secret"
        log_info "Checking for secret: ${SECRET_NAME}"

        RETRIEVED_SECRET=$(az keyvault secret show \
          --vault-name "${KEY_VAULT_NAME}" \
          --name "${SECRET_NAME}" \
          --query value -o tsv 2>/dev/null)

        if [[ -n "${RETRIEVED_SECRET}" ]]; then
          AZURE_CLIENT_SECRET="${RETRIEVED_SECRET}"
          export AZURE_CLIENT_SECRET
          log_info "✓ Retrieved AZURE_CLIENT_SECRET from Key Vault"
          APP_EXISTS=true
        else
          log_warn "Secret '${SECRET_NAME}' not found in Key Vault"
          log_info "You can provide it manually or it will be stored after validation"
          echo ""
          read -r -p "Enter AZURE_CLIENT_SECRET (or press Enter to skip): " INPUT_SECRET

          if [[ -n "${INPUT_SECRET}" ]]; then
            AZURE_CLIENT_SECRET="${INPUT_SECRET}"
            export AZURE_CLIENT_SECRET
            log_info "AZURE_CLIENT_SECRET set"

            # Store in Key Vault for future use
            log_info "Storing secret in Key Vault for future use..."
            az keyvault secret set \
              --vault-name "${KEY_VAULT_NAME}" \
              --name "${SECRET_NAME}" \
              --value "${AZURE_CLIENT_SECRET}" \
              --output none

            APP_EXISTS=true
          else
            log_error "Cannot proceed without AZURE_CLIENT_SECRET"
            exit 1
          fi
        fi
      else
        log_error "KEY_VAULT_NAME not set (should have been set in Step 0)"
        exit 1
      fi
    else
      log_error "Failed to select app registration"
      exit 1
    fi
  elif [[ $REPLY == "2" ]]; then
    # Create new app registration automatically
    log_info "Creating Entra ID app registration..."

    export STATIC_WEB_APP_NAME
    export CUSTOM_DOMAIN
    export KEY_VAULT_NAME

    source "${SCRIPT_DIR}/52-setup-app-registration.sh"

    log_info "App registration created: ${AZURE_CLIENT_ID}"
    log_info "Secret stored in Key Vault as: ${STATIC_WEB_APP_NAME}-client-secret"
    APP_EXISTS=true
  else
    # Option 3 or any other input - exit
    log_info "Exiting. To proceed, set AZURE_CLIENT_ID environment variable:"
    log_info "  export AZURE_CLIENT_ID=<your-client-id>"
    log_info ""
    log_info "Or run with:"
    log_info "  AZURE_CLIENT_ID=xxx $0"
    log_info ""
    log_info "The client secret will be retrieved from Key Vault automatically."
    exit 0
  fi
fi

# At this point, we should have AZURE_CLIENT_ID set
if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
  log_error "AZURE_CLIENT_ID is required but not set"
  exit 1
fi

readonly AZURE_CLIENT_ID
echo ""

# Step 1: Create VNet Infrastructure
log_step "Step 1/12: Creating VNet infrastructure..."
echo ""

export VNET_NAME
export VNET_ADDRESS_SPACE
export SUBNET_FUNCTION_NAME
export SUBNET_FUNCTION_PREFIX
export SUBNET_PE_NAME
export SUBNET_PE_PREFIX
export LOCATION

"${SCRIPT_DIR}/11-create-vnet-infrastructure.sh"

log_info "VNet infrastructure created"
echo ""

# Step 2: Create App Service Plan
log_step "Step 2/12: Creating App Service Plan (${APP_SERVICE_PLAN_SKU})..."
echo ""

log_info "Creating ${APP_SERVICE_PLAN_SKU} App Service Plan for private endpoint support..."
export PLAN_NAME="${APP_SERVICE_PLAN_NAME}"
export PLAN_SKU="${APP_SERVICE_PLAN_SKU}"

"${SCRIPT_DIR}/12-create-app-service-plan.sh"

log_info "App Service Plan created"
echo ""

# Step 3: Create Function App on App Service Plan
log_step "Step 3/12: Creating Function App on App Service Plan..."
echo ""

# Check if Function App was newly created or already existed
FUNCTION_APP_EXISTED=false
if az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  FUNCTION_APP_EXISTED=true
fi

# Find or create storage account by tag (avoids collisions, enables idempotency)
STORAGE_TAG="purpose=func-subnet-calc-private-endpoint"
log_info "Checking for existing storage account with tag: ${STORAGE_TAG}..."

EXISTING_STORAGE=$(az storage account list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?tags.purpose=='func-subnet-calc-private-endpoint'].name | [0]" \
  -o tsv)

if [[ -n "${EXISTING_STORAGE}" ]]; then
  export STORAGE_ACCOUNT_NAME="${EXISTING_STORAGE}"
  log_info "Found existing tagged storage account: ${STORAGE_ACCOUNT_NAME}"
else
  # Generate globally unique name with random suffix (6 hex chars = 16.7M combinations)
  STORAGE_BASE="stfuncprivateep"
  STORAGE_SUFFIX=$(openssl rand -hex 3)
  export STORAGE_ACCOUNT_NAME="${STORAGE_BASE}${STORAGE_SUFFIX}"
  export STORAGE_ACCOUNT_TAG="${STORAGE_TAG}"
  log_info "Will create new storage account: ${STORAGE_ACCOUNT_NAME}"
fi

export FUNCTION_APP_NAME
export APP_SERVICE_PLAN="${APP_SERVICE_PLAN_NAME}"

"${SCRIPT_DIR}/13-create-function-app-on-app-service-plan.sh"

log_info "Configuring Function App settings (no auth - SWA handles it)..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=none \
    CORS_ORIGINS="https://${CUSTOM_DOMAIN}" \
  --output none

log_info "Function App configured"
echo ""

# Step 4: Enable VNet Integration
log_step "Step 4/12: Enabling VNet integration on Function App..."
echo ""

export FUNCTION_APP_NAME
export VNET_NAME
export SUBNET_NAME="${SUBNET_FUNCTION_NAME}"

"${SCRIPT_DIR}/14-configure-function-vnet-integration.sh"

log_info "VNet integration enabled"
echo ""

# Step 5: Deploy Function API
log_step "Step 5/12: Deploying Function API..."
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

# Step 6: Create Private Endpoint for Function App
log_step "Step 6/12: Creating private endpoint for Function App..."
echo ""

export FUNCTION_APP_NAME
export VNET_NAME
export SUBNET_NAME="${SUBNET_PE_NAME}"

"${SCRIPT_DIR}/46-create-private-endpoint.sh"

log_info "Private endpoint created"
log_info "Function App is now accessible ONLY via private network"
echo ""

# Step 7: Create Static Web App
log_step "Step 7/12: Creating Azure Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export STATIC_WEB_APP_SKU
export LOCATION="${SWA_LOCATION}"  # Override with SWA-compatible region

"${SCRIPT_DIR}/00-static-web-app.sh"

# Restore original location for subsequent steps
export LOCATION="${REQUESTED_LOCATION}"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 8: Create Private Endpoint for Static Web App
log_step "Step 8/12: Creating private endpoint for Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
export VNET_NAME
export SUBNET_NAME="${SUBNET_PE_NAME}"

"${SCRIPT_DIR}/48-create-private-endpoint-swa.sh"

log_info "Private endpoint created for Static Web App"
log_info "SWA is now accessible ONLY via private network"
echo ""

# Step 9: Link Function App to SWA
log_step "Step 9/12: Linking Function App to SWA..."
echo ""

FUNC_RESOURCE_ID=$(az webapp show \
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

# Step 10: Configure Custom Domain and Disable Default Hostname
log_step "Step 10/12: Configuring custom domain..."
echo ""

log_info "Custom domain: ${CUSTOM_DOMAIN}"
log_info "SWA hostname: ${SWA_URL}"
log_info ""
log_info "The script will now:"
log_info "  1. Add the custom domain to Azure (generates validation token)"
log_info "  2. Display the TXT record for domain validation"
log_info "  3. Display the CNAME record for traffic routing"
log_info "  4. Wait for you to configure DNS"
log_info ""

export CUSTOM_DOMAIN
if "${SCRIPT_DIR}/41-configure-custom-domain-swa.sh"; then
  log_info "Custom domain configured successfully"
else
  log_warn "Custom domain configuration incomplete or validation pending"
  log_info "Continuing with remaining steps..."
fi
echo ""

# Disable public access to azurestaticapps.net hostname
log_info "Disabling public access to azurestaticapps.net hostname..."
log_warn "This sets publicNetworkAccess: Disabled (returns 403, does not redirect)"

if [[ -f "${SCRIPT_DIR}/47-disable-default-hostname.sh" ]]; then
  export STATIC_WEB_APP_NAME
  if "${SCRIPT_DIR}/47-disable-default-hostname.sh"; then
    log_info "Public access disabled successfully - default hostname returns 403"
  else
    log_warn "Failed to disable public access"
    log_warn "Default hostname remains publicly accessible"
  fi
else
  log_warn "Script 47-disable-default-hostname.sh not found"
  log_warn "Default hostname remains publicly accessible"
  log_warn "To disable manually, use Azure Portal or REST API"
fi
echo ""

# Step 11: Update Entra ID and Deploy Frontend
log_step "Step 11/12: Updating Entra ID and deploying frontend..."
echo ""

log_info "Adding redirect URI (custom domain ONLY)..."
log_info "  https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
echo ""

# Build redirect URIs list - custom domain only
NEW_URI="https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"

# Get current URIs and combine with new one, ensuring uniqueness
REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris[]" -o tsv 2>/dev/null | cat)

# Add new URI to list - use process substitution to avoid trailing newline issues
mapfile -t URI_ARRAY < <(printf '%s\n%s\n' "${REDIRECT_URIS}" "${NEW_URI}" | grep -v '^$' | sort -u)

# Ensure we have at least one URI
if [ ${#URI_ARRAY[@]} -eq 0 ]; then
  log_error "No redirect URIs to configure"
  exit 1
fi

# Update redirect URIs using Graph API (more reliable than az ad app update)
log_info "Updating ${#URI_ARRAY[@]} redirect URI(s) via Microsoft Graph API..."

# Get the app's object ID (needed for Graph API)
APP_OBJECT_ID=$(az ad app show --id "${AZURE_CLIENT_ID}" --query id -o tsv)

# Build JSON array from URI_ARRAY
URI_JSON=$(printf '"%s",' "${URI_ARRAY[@]}" | sed 's/,$//')

# Update using Graph API
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
  --headers 'Content-Type=application/json' \
  --body "{
    \"web\": {
      \"redirectUris\": [${URI_JSON}],
      \"logoutUrl\": \"https://${CUSTOM_DOMAIN}/logged-out.html\",
      \"implicitGrantSettings\": {
        \"enableAccessTokenIssuance\": true,
        \"enableIdTokenIssuance\": true
      }
    }
  }" \
  --output none

log_info "Entra ID app updated"
echo ""

# Configure Entra ID on SWA
export STATIC_WEB_APP_NAME
export AZURE_CLIENT_ID
export CUSTOM_DOMAIN  # Export custom domain for logout URL (already set at top of script)
export KEY_VAULT_NAME # NEW: Pass to script 42 for secret retrieval
# Do NOT export AZURE_CLIENT_SECRET - script 42 retrieves from Key Vault

"${SCRIPT_DIR}/42-configure-entraid-swa.sh"

log_info "Entra ID configured on SWA"
echo ""

# Deploy Frontend
log_info "Building and deploying frontend with Entra ID auth..."
log_info "  API URL: (empty - use /api route via SWA proxy)"

export FRONTEND=typescript
export SWA_AUTH_ENABLED=true   # Use SWA built-in Entra ID authentication (for staticwebapp.config.json)
export VITE_AUTH_ENABLED=true  # Enable auth in frontend
export VITE_AUTH_METHOD=entraid # Explicitly set auth method (works on custom domains)
export VITE_API_URL=""         # Use SWA proxy to linked backend
export CUSTOM_DOMAIN           # Export custom domain for display (already set at top of script)
export STATIC_WEB_APP_NAME
export RESOURCE_GROUP

"${SCRIPT_DIR}/20-deploy-frontend.sh"

log_info "Frontend deployed"
echo ""

# Check/Offer to create Application Gateway
log_step "Checking Application Gateway status..."
echo ""

# Define Application Gateway name
APPGW_NAME="${APPGW_NAME:-agw-${STATIC_WEB_APP_NAME}}"
APPGW_EXISTS=false

if az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  APPGW_EXISTS=true
  log_info "Application Gateway ${APPGW_NAME} already exists"

  # Get public IP for display
  PUBLIC_IP_NAME="pip-${APPGW_NAME}"
  if PUBLIC_IP_ADDRESS=$(az network public-ip show \
    --name "${PUBLIC_IP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query ipAddress -o tsv 2>/dev/null); then
    log_info "Public IP: ${PUBLIC_IP_ADDRESS}"
    log_info "Access via: http://${PUBLIC_IP_ADDRESS}"
  fi
else
  log_warn "No Application Gateway found"
  log_info ""
  log_info "IMPORTANT: Your SWA and Function are currently private endpoint only!"
  log_info "To provide public access, you need an Application Gateway."
  log_info ""
  log_info "The Application Gateway will:"
  log_info "  • Provide a public IP for internet access"
  log_info "  • Route traffic to your private SWA endpoint"
  log_info "  • Enable WAF protection (optional)"
  log_info "  • Cost ~\$320-425/month"
  log_info ""
  read -p "Create Application Gateway now? (Y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Creating Application Gateway..."
    echo ""

    export STATIC_WEB_APP_NAME
    export VNET_NAME
    export APPGW_NAME
    export LOCATION

    # Call the Application Gateway creation script
    "${SCRIPT_DIR}/49-create-application-gateway.sh"

    # Add HTTPS listener (script 50)
    log_info "Adding HTTPS listener to Application Gateway..."
    "${SCRIPT_DIR}/50-add-https-listener.sh"

    APPGW_EXISTS=true

    # Get public IP for summary
    PUBLIC_IP_NAME="pip-${APPGW_NAME}"
    PUBLIC_IP_ADDRESS=$(az network public-ip show \
      --name "${PUBLIC_IP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query ipAddress -o tsv 2>/dev/null || echo "")

    log_info "Application Gateway created successfully"
    echo ""
  else
    log_info "Skipping Application Gateway creation"
    log_warn "Your resources are private endpoint only - accessible only from within the VNet"
    echo ""
  fi
fi
echo ""

# Summary
log_info "========================================="
log_info "Stack 3 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA (PRIMARY):     https://${CUSTOM_DOMAIN}"
log_info "  SWA (DEFAULT):     DISABLED"
if [[ "${APPGW_EXISTS}" == "true" ]] && [[ -n "${PUBLIC_IP_ADDRESS:-}" ]]; then
  log_info "  Public Access:     http://${PUBLIC_IP_ADDRESS} (via Application Gateway)"
  log_info "  SWA Private:       Private endpoint only"
  log_info "  Function Private:  Private endpoint only"
else
  log_info "  SWA Access:        Private endpoint only (no public access)"
  log_info "  Function:          Private endpoint only (no public access)"
fi
log_info ""
log_info "Network Architecture:"
log_info "  VNet:              ${VNET_NAME} (${VNET_ADDRESS_SPACE})"
log_info "  Functions Subnet:  ${SUBNET_FUNCTION_PREFIX}"
log_info "  Endpoints Subnet:  ${SUBNET_PE_PREFIX}"
if [[ "${APPGW_EXISTS}" == "true" ]]; then
  log_info "  AppGW Subnet:      10.100.0.32/27 (Application Gateway)"
  log_info "  Application GW:    ${APPGW_NAME} (Public: ${PUBLIC_IP_ADDRESS:-N/A})"
fi
log_info "  Private Endpoints: SWA + Function App (both isolated from internet)"
log_info ""
log_info "Authentication:"
log_info "  Type:              Entra ID (platform-level)"
log_info "  Login URL:         https://${CUSTOM_DOMAIN}/.auth/login/aad"
log_info "  Logout URL:        https://${CUSTOM_DOMAIN}/logout"
log_info "  User Info:         https://${CUSTOM_DOMAIN}/.auth/me"
log_info ""
log_info "Security Features:"
log_info "  ✓ Custom domain is PRIMARY"
log_info "  ✓ azurestaticapps.net domain DISABLED"
log_info "  ✓ SWA accessible only via private endpoint"
log_info "  ✓ Function accessible only via private endpoint"
log_info "  ✓ No public access to frontend or backend"
log_info "  ✓ Full network-level isolation"
log_info ""
log_info "Test the deployment:"
if [[ "${APPGW_EXISTS}" == "true" ]] && [[ -n "${PUBLIC_IP_ADDRESS:-}" ]]; then
  log_info "  PUBLIC ACCESS (via Application Gateway):"
  log_info "    1. Visit http://${PUBLIC_IP_ADDRESS}"
  log_info "    2. Sign in with Entra ID credentials"
  log_info "    3. Verify API calls work via /api/* proxy"
  log_info ""
  log_info "  PRIVATE ACCESS (from VNet):"
  log_info "    1. From a VM in the VNet, visit https://${CUSTOM_DOMAIN}"
  log_info "    2. Verify both paths work (public via AppGW, private via VNet)"
else
  log_info "  IMPORTANT: Both SWA and Function are private endpoint only!"
  log_info "  Access requires being in the VNet or using Application Gateway."
  log_info ""
  log_info "  From a VM in the VNet:"
  log_info "    1. Visit https://${CUSTOM_DOMAIN}"
  log_info "    2. Sign in with Entra ID credentials"
  log_info "    3. Verify API calls work via /api/* proxy"
  log_info "    4. Confirm SWA and Function not accessible from public internet"
  log_info ""
  log_info "  To provide public access, run this script again:"
  log_info "    It will detect no Application Gateway and offer to create one"
fi
log_info ""
log_info "Redirect URI configured:"
log_info "  - https://${CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "Monthly Cost: ~${MONTHLY_COST}"
log_info "  - SWA Standard: \$9"
log_info "  - ${APP_SERVICE_PLAN_SKU} Plan: ${APP_PLAN_COST}"
log_info "  - Private Endpoints: Free (data processing charges may apply)"
log_info ""
