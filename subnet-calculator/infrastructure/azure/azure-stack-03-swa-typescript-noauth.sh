#!/usr/bin/env bash
#
# stack-03-swa-typescript-noauth.sh - Deploy Stack 03: SWA TypeScript (No Auth)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Free)         │
#   │ - TypeScript Vite SPA               │
#   │ - Modern reactive UI                │
#   │ - All API calls visible in browser  │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS (public)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Python 3.11 FastAPI               │
#   │ - Public endpoint                   │
#   │ - NO AUTHENTICATION                 │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (modern SPA)
#   - Backend: Function App (Consumption plan, public)
#   - Authentication: None - completely open
#   - Use case: Public API testing, demos
#   - Cost: ~$0 (Free tier SWA + Consumption)
#
# Usage:
#   ./stack-03-swa-typescript-noauth.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-03-swa-typescript-noauth.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   STATIC_WEB_APP_NAME  - Static Web App name (default: swa-subnet-calc-noauth)
#   FUNCTION_APP_NAME    - Function App name (default: func-subnet-calc-{random})
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: noauth)

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
# (e.g., uksouth → westeurope, eastus → eastus2, etc.)
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-noauth}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-noauth}"

# Banner
echo ""
log_info "========================================="
log_info "Stack 03: SWA TypeScript (No Auth)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA"
log_info "  Backend:  Function App (Consumption)"
log_info "  Auth:     None - completely public"
log_info "  Cost:     ~\$9/month (Standard tier SWA + Consumption Function)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier - custom domain support)"
log_info "  2. Azure Function App (Consumption)"
log_info "  3. TypeScript Vite frontend"
log_info "  4. Function App API (no authentication)"
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
log_step "Step 1/4: Creating Azure Static Web App..."
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

# Step 3: Deploy Function App code (no authentication)
log_step "Step 3/4: Deploying Function App code (no authentication)..."
echo ""

export FUNCTION_APP_NAME
export DISABLE_AUTH=true

"${SCRIPT_DIR}/22-deploy-function-zip.sh"

log_info "Function App deployed: ${FUNCTION_APP_URL}"
log_info "Authentication: Disabled (public access)"
echo ""

# Wait for Function App to be fully ready
log_info "Waiting for Function App to be fully ready (30 seconds)..."
sleep 30

# Step 4: Deploy frontend with API URL
log_step "Step 4/4: Deploying TypeScript Vite frontend..."
echo ""

export FRONTEND=typescript
export API_URL="${FUNCTION_APP_URL}"

"${SCRIPT_DIR}/20-deploy-frontend.sh"

log_info "Frontend deployed: https://${SWA_URL}"
log_info "Frontend configured with API: ${FUNCTION_APP_URL}"
echo ""

# Final summary
echo ""
log_info "========================================="
log_info "Stack 03 deployment complete!"
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
log_info "  # Test API health"
log_info "  curl ${FUNCTION_APP_URL}/api/v1/health"
log_info ""
log_info "  # Test IPv4 calculation"
log_info "  curl '${FUNCTION_APP_URL}/api/v1/ipv4/subnet-info' \\"
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
log_info "  - TypeScript Vite frontend (modern SPA)"
log_info "  - Function App API (Consumption plan)"
log_info "  - No authentication - completely public"
log_info "  - Cost: ~\$0 (Free tier SWA + Consumption)"
log_info ""
log_info "Note: Initial deployment may take 1-2 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
