#!/usr/bin/env bash
#
# stack-09-swa-typescript-managed-auth.sh - Deploy Stack 09: SWA TypeScript (Managed + Entra ID)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Standard)     │
#   │ - TypeScript Vite SPA               │
#   │ - Entra ID SSO (platform auth)      │
#   │ - /api/* → Managed Functions        │
#   │   (SWA deploys & manages)           │
#   │ - Region: westeurope (managed)      │
#   │ - HttpOnly cookies (XSS protected)  │
#   │ - CSRF protection (automatic)       │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (modern SPA)
#   - Backend: Managed Functions (deployed by SWA, westeurope)
#   - Authentication: Entra ID platform authentication
#   - Use case: Enterprise app with managed simplicity
#   - Cost: ~$9/month (Standard tier SWA, managed functions included)
#
# Key Differences from Other Stacks:
#   - Combines managed functions (Stack 04) with Entra ID auth (Stack 05+)
#   - No separate function app (embedded in SWA)
#   - Region locked to westeurope (EU compliance)
#   - Automatic deployment and scaling
#   - Enterprise SSO with managed backend
#
# Usage:
#   AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=yyy ./stack-09-swa-typescript-managed-auth.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-09-swa-typescript-managed-auth.sh
#
# Environment variables (required):
#   AZURE_CLIENT_ID      - Entra ID app registration client ID
#   AZURE_CLIENT_SECRET  - Entra ID app registration client secret
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: managed-auth)

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
PROJECT_ROOT="${SCRIPT_DIR}/../.."

# Configuration
readonly LOCATION="${LOCATION:-westeurope}"  # Managed functions region
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-managed-auth}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-managed-auth}"

# Check required environment variables
if [[ -z "${AZURE_CLIENT_ID:-}" ]] || [[ -z "${AZURE_CLIENT_SECRET:-}" ]]; then
  log_error "Required environment variables not set"
  log_error ""
  log_error "Entra ID authentication requires:"
  log_error "  AZURE_CLIENT_ID      - Entra ID app registration client ID"
  log_error "  AZURE_CLIENT_SECRET  - Entra ID app registration client secret"
  log_error ""
  log_error "Create an Entra ID app registration:"
  log_error "  1. Azure Portal → Entra ID → App registrations → New registration"
  log_error "  2. Name: subnet-calculator-managed-auth"
  log_error "  3. Redirect URI: https://${STATIC_WEB_APP_NAME}.azurestaticapps.net/.auth/login/aad/callback"
  log_error "  4. Create client secret: Certificates & secrets → New client secret"
  log_error "  5. Note the Application (client) ID and client secret value"
  log_error ""
  log_error "Then run:"
  log_error "  AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=yyy ./stack-09-swa-typescript-managed-auth.sh"
  exit 1
fi

# Banner
echo ""
log_info "========================================="
log_info "Stack 09: SWA TypeScript (Managed + Entra ID)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA"
log_info "  Backend:  Managed Functions (westeurope)"
log_info "  Auth:     Entra ID (platform auth)"
log_info "  Cost:     ~\$9/month (Standard tier SWA)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Managed Functions (deployed by SWA)"
log_info "  3. TypeScript Vite frontend"
log_info "  4. Entra ID platform authentication"
log_info ""
log_info "Authentication:"
log_info "  Type:         Entra ID SSO (platform auth)"
log_info "  Client ID:    ${AZURE_CLIENT_ID}"
log_info "  Cookie:       HttpOnly (XSS protected)"
log_info "  CSRF:         Automatic protection"
log_info ""
log_info "Note: Managed functions are deployed to westeurope."
log_info "      Best for EU/UK deployments with enterprise SSO."
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

read -r -p "Proceed with deployment? (Y/n): " confirm
confirm=${confirm:-y}
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  log_info "Cancelled"
  exit 0
fi
echo ""

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    log_error "Create one with: az group create --name rg-subnet-calc --location ${LOCATION}"
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
log_step "Step 1/3: Creating Azure Static Web App with managed functions..."
echo ""

export RESOURCE_GROUP
export STATIC_WEB_APP_NAME
export LOCATION
export STATIC_WEB_APP_SKU="Standard"
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

# Step 2: Configure Entra ID authentication
log_step "Step 2/3: Configuring Entra ID authentication..."
echo ""

log_info "Setting Entra ID configuration..."
az staticwebapp appsettings set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --setting-names \
    AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
    AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}" \
  --output none

log_info "Entra ID authentication configured"
log_info ""
log_info "Important: Update your Entra ID app registration redirect URI:"
log_info "  Current SWA URL: https://${SWA_URL}"
log_info "  Redirect URI: https://${SWA_URL}/.auth/login/aad/callback"
log_info ""
log_info "Steps:"
log_info "  1. Azure Portal → Entra ID → App registrations"
log_info "  2. Select your app registration (${AZURE_CLIENT_ID})"
log_info "  3. Authentication → Add a redirect URI"
log_info "  4. Type: Web"
log_info "  5. URI: https://${SWA_URL}/.auth/login/aad/callback"
log_info "  6. Save"
echo ""

# Step 3: Deploy frontend and managed functions with Entra ID config
log_step "Step 3/3: Deploying TypeScript Vite frontend with managed functions..."
echo ""

# Build frontend
log_info "Building TypeScript Vite frontend..."
cd "${PROJECT_ROOT}/frontend-typescript-vite"

# Install dependencies
if [[ ! -d "node_modules" ]]; then
  log_info "Installing dependencies..."
  npm install --silent
fi

# Build for production
log_info "Building for production..."
npm run build --silent

# Copy staticwebapp-entraid.config.json to output
log_info "Copying Entra ID configuration..."
cp "${SCRIPT_DIR}/staticwebapp-entraid.config.json" dist/staticwebapp.config.json

# Get deployment token
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Deploy using Azure Static Web Apps CLI with managed functions
log_info "Deploying to Azure Static Web App..."
npx @azure/static-web-apps-cli deploy \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --app-location "." \
  --output-location "dist" \
  --api-location "../api-fastapi-azure-function" \
  --no-use-keychain

log_info "Frontend and managed functions deployed: https://${SWA_URL}"
echo ""

# Wait for deployment to propagate
log_info "Waiting for deployment to propagate (30 seconds)..."
sleep 30

# Final summary
echo ""
log_info "========================================="
log_info "Stack 09 deployment complete!"
log_info "========================================="
log_info ""
log_info "Resources created:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info ""
log_info "URLs:"
log_info "  Frontend (Azure):  https://${SWA_URL}"
log_info "  API endpoint:      https://${SWA_URL}/api/v1/health"
log_info "  API Docs:          https://${SWA_URL}/api/v1/docs"
log_info "  Login:             https://${SWA_URL}/.auth/login/aad"
log_info "  Logout:            https://${SWA_URL}/.auth/logout"
log_info ""
log_info "Authentication:"
log_info "  Type:      Entra ID SSO (platform auth)"
log_info "  Client ID: ${AZURE_CLIENT_ID}"
log_info "  Cookie:    HttpOnly (XSS protected)"
log_info "  CSRF:      Automatic protection"
log_info ""
log_info "DNS Configuration:"
log_info "  Custom Domain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "  Add CNAME record in Cloudflare:"
log_info "    Name:   ${SUBDOMAIN}"
log_info "    Type:   CNAME"
log_info "    Target: ${SWA_URL}"
log_info "    Proxy:  DNS only (grey cloud)"
log_info ""
log_info "  After DNS propagation:"
log_info "    1. Configure custom domain on SWA: ./40-configure-custom-domain-swa.sh"
log_info "    2. Update Entra ID redirect URI to: https://${SUBDOMAIN}.${CUSTOM_DOMAIN}/.auth/login/aad/callback"
log_info ""
log_info "Test commands:"
log_info "  # Test API (requires authentication)"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "  # Login directly"
log_info "  open https://${SWA_URL}/.auth/login/aad"
log_info ""
log_info "  # Check auth status"
log_info "  curl https://${SWA_URL}/.auth/me"
log_info ""
log_info "Architecture summary:"
log_info "  - TypeScript Vite frontend with Entra ID login"
log_info "  - Managed Functions (westeurope, deployed by SWA)"
log_info "  - Platform authentication (SWA handles all auth)"
log_info "  - HttpOnly cookies (XSS protected)"
log_info "  - Automatic CSRF protection"
log_info "  - Cost: ~\$9/month (Standard tier SWA)"
log_info ""
log_info "Security benefits:"
log_info "  - Enterprise SSO (Entra ID)"
log_info "  - HttpOnly cookies (not accessible from JavaScript)"
log_info "  - Automatic CSRF token handling"
log_info "  - No token management needed in frontend"
log_info "  - Managed functions (no separate resource to secure)"
log_info ""
log_info "Note: Managed functions are deployed in westeurope."
log_info "      Initial deployment may take 2-3 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info "      Remember to update Entra ID redirect URI!"
log_info ""
log_info "========================================="
echo ""
