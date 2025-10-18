#!/usr/bin/env bash
#
# stack-08-swa-typescript-jwt.sh - Deploy Stack 08: SWA TypeScript (JWT Auth)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Standard)     │
#   │ - TypeScript Vite SPA               │
#   │ - JWT login form                    │
#   │ - Token in localStorage/sessionStorage │
#   │ - Manual token management           │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS + JWT Bearer token
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - JWT AUTHENTICATION REQUIRED       │
#   │ - Argon2 password hashing           │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (JWT login flow)
#   - Backend: Function App (Consumption plan, JWT auth)
#   - Authentication: Application-level JWT (NOT Entra ID)
#   - Use case: Custom user management, API key alternative
#   - Cost: ~$9/month (Standard tier SWA + Consumption Function)
#
# Key Differences from Entra ID Stacks:
#   - Application authentication (not platform authentication)
#   - JWT tokens visible in browser (can be inspected)
#   - Custom user database (Argon2 hashed passwords)
#   - Manual token refresh required
#   - No enterprise SSO
#
# Usage:
#   ./stack-08-swa-typescript-jwt.sh
#   JWT_USERNAME=myuser JWT_PASSWORD=mypass ./stack-08-swa-typescript-jwt.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth for UK, auto-detected)
#   STATIC_WEB_APP_NAME  - Static Web App name (default: swa-subnet-calc-jwt)
#   FUNCTION_APP_NAME    - Function App name (default: func-subnet-calc-{random})
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: jwt)
#   JWT_USERNAME         - JWT test username (default: demo)
#   JWT_PASSWORD         - JWT test password (default: password123)

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
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-jwt}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-jwt}"
readonly JWT_USERNAME="${JWT_USERNAME:-demo}"
readonly JWT_PASSWORD="${JWT_PASSWORD:-password123}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 08: SWA TypeScript (JWT Auth)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA"
log_info "  Backend:  Function App (Consumption)"
log_info "  Auth:     JWT (application-level)"
log_info "  Cost:     ~\$9/month (Standard SWA + Consumption)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Azure Function App (Consumption, JWT required)"
log_info "  3. TypeScript Vite frontend (JWT login)"
log_info "  4. Application-level JWT authentication"
log_info ""
log_info "Authentication details:"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info "  Note: Tokens stored in browser localStorage"
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
log_step "Step 1/4: Creating Azure Static Web App..."
echo ""

export RESOURCE_GROUP
export STATIC_WEB_APP_NAME
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

# Step 2: Create Function App
log_step "Step 2/4: Creating Azure Function App..."
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

FUNCTION_APP_URL="https://$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.defaultHostName" -o tsv 2>/dev/null || echo "")"

if [[ "${FUNCTION_APP_URL}" == "https://" ]]; then
  log_error "Failed to get Function App URL"
  exit 1
fi

log_info "Function App created: ${FUNCTION_APP_URL}"
echo ""

# Step 3: Deploy Function App code with JWT authentication enabled
log_step "Step 3/4: Deploying Function App code with JWT authentication..."
echo ""

export FUNCTION_APP_NAME
export ENABLE_AUTH=true
export JWT_USERNAME
export JWT_PASSWORD

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed: ${FUNCTION_APP_URL}"
log_info "Authentication: JWT enabled"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD} (Argon2 hashed)"
echo ""

# Wait for Function App to be fully ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 4: Deploy frontend with API URL and JWT auth enabled
log_step "Step 4/4: Deploying TypeScript Vite frontend with JWT auth..."
echo ""

# Build frontend with JWT auth enabled
cd "${PROJECT_ROOT}/frontend-typescript-vite"

# Install dependencies
if [[ ! -d "node_modules" ]]; then
  log_info "Installing dependencies..."
  npm install --silent
fi

# Build with JWT auth enabled
log_info "Building frontend with JWT authentication enabled..."
export VITE_AUTH_ENABLED=true
export VITE_JWT_USERNAME="${JWT_USERNAME}"
export VITE_JWT_PASSWORD="${JWT_PASSWORD}"
export VITE_API_URL="${FUNCTION_APP_URL}"

npm run build --silent

# Get deployment token
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Deploy to SWA (BYO functions, so api-location is empty)
log_info "Deploying to Azure Static Web App..."
npx @azure/static-web-apps-cli deploy \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --app-location "." \
  --output-location "dist" \
  --api-location "" \
  --no-use-keychain

log_info "Frontend deployed: https://${SWA_URL}"
log_info "Frontend configured with API: ${FUNCTION_APP_URL}"
echo ""

# Wait for deployment to propagate
log_info "Waiting for deployment to propagate (30 seconds)..."
sleep 30

# Final summary
echo ""
log_info "========================================="
log_info "Stack 08 deployment complete!"
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
log_info "Authentication:"
log_info "  Type:     JWT (application-level)"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info "  Storage:  Browser localStorage"
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
log_info "  After DNS propagation, configure custom domain on SWA:"
log_info "    ./40-configure-custom-domain-swa.sh"
log_info ""
log_info "Test commands:"
log_info "  # Get JWT token"
log_info "  TOKEN=\$(curl '${FUNCTION_APP_URL}/api/v1/auth/token' \\"
log_info "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
log_info "    -d 'username=${JWT_USERNAME}&password=${JWT_PASSWORD}' | jq -r .access_token)"
log_info ""
log_info "  # Test authenticated endpoint"
log_info "  curl '${FUNCTION_APP_URL}/api/v1/ipv4/subnet-info' \\"
log_info "    -H 'Authorization: Bearer \$TOKEN' \\"
log_info "    -H 'Content-Type: application/json' \\"
log_info "    -d '{\"network\":\"10.0.0.0/24\",\"mode\":\"simple\"}'"
log_info ""
log_info "  # Open frontend in browser (Azure URL)"
log_info "  open https://${SWA_URL}"
log_info ""
log_info "  # Open frontend in browser (Custom domain - after DNS)"
log_info "  open https://${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Architecture summary:"
log_info "  - TypeScript Vite frontend with JWT login"
log_info "  - Function App API with JWT authentication"
log_info "  - Application-level auth (not platform/Entra ID)"
log_info "  - Tokens stored in browser localStorage"
log_info "  - Cost: ~\$9/month (Standard SWA + Consumption)"
log_info ""
log_info "Security notes:"
log_info "  - JWT tokens visible in browser (DevTools, localStorage)"
log_info "  - No XSS protection like HttpOnly cookies"
log_info "  - Suitable for API keys, custom user management"
log_info "  - For enterprise SSO, use Entra ID stacks (05a-09)"
log_info ""
log_info "Note: Initial deployment may take 1-2 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
