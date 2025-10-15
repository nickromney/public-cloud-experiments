#!/usr/bin/env bash
#
# stack-04-swa-typescript-jwt.sh - Deploy Stack 04: SWA TypeScript (JWT Auth)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Free)         │
#   │ - TypeScript Vite SPA               │
#   │ - JWT login flow                    │
#   │ - Token visible in browser          │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS + JWT Bearer token
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - REQUIRES JWT AUTHENTICATION       │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (modern SPA with auth)
#   - Backend: Function App (Consumption plan, JWT required)
#   - Authentication: JWT tokens - API validates tokens
#   - Use case: Authenticated API, custom user management
#   - Cost: ~$0 (Free tier SWA + Consumption)
#
# Usage:
#   ./stack-04-swa-typescript-jwt.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-04-swa-typescript-jwt.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
# LOCATION - Let 00-static-web-app.sh auto-detect from resource group and map to valid SWA region
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-jwt}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-jwt}"
readonly JWT_USERNAME="${JWT_USERNAME:-demo}"
readonly JWT_PASSWORD="${JWT_PASSWORD:-password123}"

# Generate JWT secret key if not provided
if [[ -z "${JWT_SECRET_KEY:-}" ]]; then
  JWT_SECRET_KEY=$(openssl rand -base64 32)
  log_info "Generated JWT secret key"
fi
readonly JWT_SECRET_KEY

# Banner
echo ""
log_info "========================================="
log_info "Stack 04: SWA TypeScript (JWT Auth)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA with auth"
log_info "  Backend:  Function App (Consumption)"
log_info "  Auth:     JWT tokens required"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption Function)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier - custom domain support)"
log_info "  2. Azure Function App (Consumption)"
log_info "  3. TypeScript Vite frontend with JWT login"
log_info "  4. Function App API (JWT authentication required)"
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

# Step 1: Create Static Web App
log_step "Step 1/5: Creating Azure Static Web App..."
echo ""

export STATIC_WEB_APP_NAME
# Don't export LOCATION - let 00-static-web-app.sh auto-detect and map from resource group
"${SCRIPT_DIR}/00-static-web-app.sh"

# Extract Static Web App details
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  RG_COUNT=$(az group list --query "length(@)" -o tsv)
  if [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected resource group: ${RESOURCE_GROUP}"
  else
    log_error "Could not auto-detect resource group. Please set RESOURCE_GROUP environment variable."
    exit 1
  fi
fi

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
      --query "sort_by(@, &createdTime)[-1].name" -o tsv)
  else
    log_error "No Function App found after creation"
    exit 1
  fi
fi

FUNCTION_APP_URL="https://$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")"

if [[ "${FUNCTION_APP_URL}" == "https://" ]]; then
  log_error "Failed to get Function App URL"
  exit 1
fi

log_info "Function App created: ${FUNCTION_APP_URL}"
echo ""

# Step 3: Deploy Function App code with JWT authentication
log_step "Step 3/5: Deploying Function App code (JWT authentication)..."
echo ""

export FUNCTION_APP_NAME
unset DISABLE_AUTH  # Ensure JWT auth is enabled

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed: ${FUNCTION_APP_URL}"
log_info "Authentication: JWT tokens required"
echo ""

# Step 4: Configure JWT secret key
log_step "Step 4/5: Configuring JWT secret key..."
echo ""

log_info "Setting JWT secret key in Function App..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings "JWT_SECRET_KEY=${JWT_SECRET_KEY}" \
  --output none

log_info "JWT secret key configured"
echo ""

# Wait for Function App to be fully ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 5: Deploy frontend with API URL and JWT config
log_step "Step 5/5: Deploying TypeScript Vite frontend with JWT configuration..."
echo ""

# Build frontend with JWT configuration
log_info "Building TypeScript Vite frontend with JWT enabled..."

FRONTEND_DIR="${SCRIPT_DIR}/../../frontend-typescript-vite"
cd "${FRONTEND_DIR}"

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
  log_info "Installing npm dependencies..."
  npm install
fi

# Build with JWT configuration
log_info "Building production bundle with JWT auth..."
export VITE_API_URL="${FUNCTION_APP_URL}"
export VITE_AUTH_ENABLED="true"
export VITE_JWT_USERNAME="${JWT_USERNAME}"
export VITE_JWT_PASSWORD="${JWT_PASSWORD}"

npm run build

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
log_info "Stack 04 deployment complete!"
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
log_info "  Method:   JWT (HS256)"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info "  Secret:   (stored securely in Function App)"
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
log_info "  # Get JWT token (returns token)"
log_info "  curl '${FUNCTION_APP_URL}/api/v1/auth/token' \\"
log_info "    -H 'Content-Type: application/json' \\"
log_info "    -d '{\"username\":\"${JWT_USERNAME}\",\"password\":\"${JWT_PASSWORD}\"}'"
log_info ""
log_info "  # Test API with token (save token from above)"
log_info "  TOKEN=\$(curl -s '${FUNCTION_APP_URL}/api/v1/auth/token' \\"
log_info "    -H 'Content-Type: application/json' \\"
log_info "    -d '{\"username\":\"${JWT_USERNAME}\",\"password\":\"${JWT_PASSWORD}\"}' | jq -r .access_token)"
log_info ""
log_info "  curl '${FUNCTION_APP_URL}/api/v1/ipv4/subnet-info' \\"
log_info "    -H \"Authorization: Bearer \${TOKEN}\" \\"
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
log_info "  - TypeScript Vite frontend (modern SPA with JWT login)"
log_info "  - Function App API (Consumption plan with JWT validation)"
log_info "  - JWT authentication - API requires valid tokens"
log_info "  - Cost: ~\$0 (Free tier SWA + Consumption)"
log_info ""
log_info "Note: Initial deployment may take 1-2 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
