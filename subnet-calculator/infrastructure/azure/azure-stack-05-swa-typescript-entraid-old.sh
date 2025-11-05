#!/usr/bin/env bash
#
# stack-05-swa-typescript-entraid.sh - Deploy Stack 05: SWA TypeScript (Entra ID Auth)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Free)         │
#   │ - TypeScript Vite SPA               │
#   │ - Entra ID SSO login               │
#   │ - Opaque HttpOnly cookies          │
#   │ - XSS/CSRF protected                │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS + Platform Auth
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - NO APP-LEVEL AUTH (SWA handles)   │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (modern SPA with Entra ID)
#   - Backend: Function App (Consumption plan, no auth needed)
#   - Authentication: Entra ID platform authentication (SWA handles)
#   - Use case: Enterprise SSO, production security
#   - Cost: ~$0 (Free tier SWA + Consumption)
#
# Usage:
#   ./stack-05-swa-typescript-entraid.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-05-swa-typescript-entraid.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   STATIC_WEB_APP_NAME  - Static Web App name (default: swa-subnet-calc-entraid)
#   FUNCTION_APP_NAME    - Function App name (default: func-subnet-calc-{random})
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: entraid)
#   AZURE_CLIENT_ID      - Entra ID app client ID (required for auth)
#   AZURE_CLIENT_SECRET  - Entra ID app client secret (required for auth)

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
# LOCATION - Let 00-static-web-app.sh auto-detect from resource group and map to valid SWA region
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-entraid}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-entraid}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 05: SWA TypeScript (Entra ID Auth)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA with Entra ID"
log_info "  Backend:  Function App (Consumption)"
log_info "  Auth:     Entra ID platform authentication"
log_info "  Cost:     ~\$9/month (Standard tier REQUIRED for Entra ID)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier - required for Entra ID)"
log_info "  2. Azure Function App (Consumption, no auth)"
log_info "  3. TypeScript Vite frontend"
log_info "  4. SWA platform authentication (Entra ID)"
log_info ""
log_info "========================================="
echo ""

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Show current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
log_info "Current subscription: ${SUBSCRIPTION_NAME}"
log_info "Subscription ID: ${SUBSCRIPTION_ID}"
echo ""

# Check if Entra ID credentials are provided
if [[ -z "${AZURE_CLIENT_ID:-}" ]] || [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_warn "========================================="
  log_warn "ENTRA ID SETUP REQUIRED"
  log_warn "========================================="
  log_warn ""
  log_warn "To enable Entra ID authentication, you need to:"
  log_warn "  1. Create an App Registration in Entra ID"
  log_warn "  2. Set redirect URI to your SWA URL"
  log_warn "  3. Create a client secret"
  log_warn "  4. Set environment variables:"
  log_warn "     export AZURE_CLIENT_ID='<your-client-id>'"
  log_warn "     export AZURE_CLIENT_SECRET='<your-client-secret>'"
  log_warn ""
  log_warn "For now, the SWA will be deployed but authentication will not work"
  log_warn "until you configure these settings."
  log_warn ""
  log_warn "See: subnet-calculator/SWA-ENTRA-AUTH.md for full setup guide"
  log_warn ""
  log_warn "========================================="
  echo ""
  read -r -p "Continue without Entra ID credentials? (y/N): " confirm
  confirm=${confirm:-n}
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled. Configure Entra ID first, then re-run this script."
    exit 0
  fi
fi

read -r -p "Proceed with deployment? (Y/n): " confirm
confirm=${confirm:-y}
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  log_info "Cancelled"
  exit 0
fi
echo ""

# Auto-detect or prompt for RESOURCE_GROUP before calling subscripts
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    log_error "Create one with: az group create --name rg-subnet-calc --location uksouth"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    # Source selection utilities
    source "${SCRIPT_DIR}/lib/selection-utils.sh"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
  echo ""
fi

# Step 1: Create Static Web App
log_step "Step 1/5: Creating Azure Static Web App..."
echo ""

export RESOURCE_GROUP
export STATIC_WEB_APP_NAME
# Don't export LOCATION - let 00-static-web-app.sh auto-detect and map from resource group
"${SCRIPT_DIR}/00-static-web-app.sh"

SWA_URL=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv 2>/dev/null || echo "")

if [[ -z "${SWA_URL}" ]]; then
  log_error "Failed to get Static Web App URL"
  exit 1
fi

log_info "Static Web App created: https://${SWA_URL}"
echo ""

# Step 2: Create Function App
log_step "Step 2/5: Creating Azure Function App..."
echo ""

export RESOURCE_GROUP
"${SCRIPT_DIR}/10-function-app.sh"

# Extract Function App details
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
    # Get the most recently created Function App
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" \
      --query "sort_by(@, &lastModifiedTimeUtc)[-1].name" -o tsv)
  else
    log_error "No Function App found after creation"
    exit 1
  fi
fi

FUNCTION_APP_URL="https://$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv 2>/dev/null || echo "")"

if [[ "${FUNCTION_APP_URL}" == "https://" ]]; then
  log_error "Failed to get Function App URL"
  exit 1
fi

log_info "Function App created: ${FUNCTION_APP_URL}"
echo ""

# Step 3: Deploy Function App code (no authentication - SWA handles auth)
log_step "Step 3/5: Deploying Function App code (no authentication)..."
echo ""

log_info "Note: Function App has no authentication because SWA handles auth at platform level"

export FUNCTION_APP_NAME
export DISABLE_AUTH=true

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed: ${FUNCTION_APP_URL}"
log_info "Authentication: Disabled (SWA handles authentication)"
echo ""

# Wait for Function App to be fully ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 4: Configure SWA with Entra ID settings
log_step "Step 4/5: Configuring SWA authentication settings..."
echo ""

if [[ -n "${AZURE_CLIENT_ID:-}" ]] && [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_info "Configuring Entra ID app settings..."

  az staticwebapp appsettings set \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --setting-names \
      AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
      AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
    --output none

  log_info "Entra ID app settings configured"
else
  log_warn "Skipping Entra ID configuration (credentials not provided)"
  log_warn "Authentication will not work until you configure:"
  log_warn "  az staticwebapp appsettings set \\"
  log_warn "    --name ${STATIC_WEB_APP_NAME} \\"
  log_warn "    --resource-group ${RESOURCE_GROUP} \\"
  log_warn "    --setting-names \\"
  log_warn "      AZURE_CLIENT_ID='<your-client-id>' \\"
  log_warn "      AZURE_CLIENT_SECRET='<your-client-secret>'"
fi
echo ""

# Step 5: Deploy frontend with staticwebapp.config.json
log_step "Step 5/5: Deploying TypeScript Vite frontend with Entra ID config..."
echo ""

# Build frontend
log_info "Building TypeScript Vite frontend..."

FRONTEND_DIR="${SCRIPT_DIR}/../../frontend-typescript-vite"
SUBNET_CALC_DIR="${SCRIPT_DIR}/../.."

cd "${FRONTEND_DIR}"

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
  log_info "Installing npm dependencies..."
  npm install
fi

# Build with standard configuration (no auth in app, SWA handles it)
log_info "Building production bundle..."
export VITE_API_URL="${FUNCTION_APP_URL}"
unset VITE_AUTH_ENABLED  # No app-level auth, SWA handles it

npm run build

# Copy staticwebapp.config.json to dist directory
log_info "Copying staticwebapp.config.json for Entra ID authentication..."
if [[ -f "${SUBNET_CALC_DIR}/staticwebapp.config.json" ]]; then
  cp "${SUBNET_CALC_DIR}/staticwebapp.config.json" dist/
  log_info "staticwebapp.config.json copied to build output"
else
  log_warn "staticwebapp.config.json not found at ${SUBNET_CALC_DIR}/staticwebapp.config.json"
  log_warn "Creating default configuration..."
  cat > dist/staticwebapp.config.json <<'EOF'
{
  "$schema": "https://json.schemastore.org/staticwebapp.config.json",
  "routes": [
    {
      "route": "/api/*",
      "allowedRoles": ["authenticated"]
    },
    {
      "route": "/*",
      "allowedRoles": ["authenticated"]
    }
  ],
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/api/*", "/*.{css,scss,js,png,gif,ico,jpg,svg}"]
  },
  "responseOverrides": {
    "401": {
      "redirect": "/.auth/login/aad",
      "statusCode": 302
    }
  },
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/common/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID",
          "clientSecretSettingName": "AZURE_CLIENT_SECRET"
        }
      }
    }
  },
  "globalHeaders": {
    "cache-control": "no-cache, no-store, must-revalidate"
  }
}
EOF
fi

# Deploy using SWA CLI
log_info "Deploying to Azure Static Web App..."

# Get deployment token
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Check if SWA CLI is installed
if ! command -v swa &>/dev/null; then
  log_warn "Azure Static Web Apps CLI not found. Installing globally..."
  npm install -g @azure/static-web-apps-cli
fi

swa deploy \
  --app-location dist \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --env production \
  --api-language node \
  --api-version 20

log_info "Frontend deployed: https://${SWA_URL}"
log_info "Frontend configured with API: ${FUNCTION_APP_URL}"
echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 05 deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Function App:   ${FUNCTION_APP_NAME}"
log_info ""
log_info "URLs:"
log_info "  Frontend (Azure):  https://${SWA_URL}"
log_info "  Backend API:       ${FUNCTION_APP_URL}"
log_info "  API Docs:          ${FUNCTION_APP_URL}/api/v1/docs"
log_info "  API Health:        ${FUNCTION_APP_URL}/api/v1/health"
log_info ""

if [[ -n "${AZURE_CLIENT_ID:-}" ]] && [[ -n "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_info "Authentication:"
  log_info "  Method:    Entra ID (Azure AD) SSO"
  log_info "  Provider:  Azure Active Directory"
  log_info "  Client ID: ${AZURE_CLIENT_ID}"
  log_info "  Status:    Configured"
else
  log_warn "Authentication:"
  log_warn "  Method:    Entra ID (NOT CONFIGURED)"
  log_warn "  Status:    Authentication will not work until you:"
  log_warn "             1. Create Entra ID App Registration"
  log_warn "             2. Configure redirect URI: https://${SWA_URL}/.auth/login/aad/callback"
  log_warn "             3. Set app settings with client ID and secret"
  log_warn ""
  log_warn "  See: subnet-calculator/SWA-ENTRA-AUTH.md for full guide"
fi
echo ""

log_info "DNS Configuration:"
log_info "  Custom Domain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  Add CNAME record in Cloudflare:"
log_info "    Name:   ${SUBDOMAIN}"
log_info "    Type:   CNAME"
log_info "    Target: ${SWA_URL}"
log_info "    Proxy:  DNS only (grey cloud)"
log_info ""
log_info "  After DNS propagation, configure custom domain on SWA:"
log_info "    ./40-configure-custom-domain-swa.sh"
log_info ""
log_info "Test commands:"
log_info "  # Check auth status (will redirect to login if not authenticated)"
log_info "  curl https://${SWA_URL}/.auth/me"
log_info ""
log_info "  # Open frontend in browser (Azure URL)"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "  # Open frontend in browser (Custom domain - after DNS)"
log_info "  open https://${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Architecture summary:"
log_info "  - TypeScript Vite frontend (modern SPA)"
log_info "  - SWA platform authentication (Entra ID)"
log_info "  - Function App API (no auth - SWA proxies and adds user context)"
log_info "  - Opaque HttpOnly cookies (XSS/CSRF protected)"
log_info "  - Cost: ~\$0 (Free tier SWA + Consumption)"
log_info ""
log_info "Security benefits vs JWT (Stack 04):"
log_info "  - Tokens not visible to JavaScript (HttpOnly cookies)"
log_info "  - Automatic CSRF protection (SameSite cookies)"
log_info "  - No token management in frontend code"
log_info "  - Enterprise SSO integration"
log_info ""
log_info "Note: Initial deployment may take 1-2 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
