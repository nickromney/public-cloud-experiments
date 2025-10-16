#!/usr/bin/env bash
#
# stack-04-swa-typescript-managed.sh - Deploy Stack 04: SWA TypeScript (Managed Functions)
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ Azure Static Web App (Standard)     │
#   │ - TypeScript Vite SPA               │
#   │ - /api/* → Managed Functions        │
#   │   (SWA deploys & manages)           │
#   │ - Region: westeurope (managed)      │
#   │ - NO AUTHENTICATION                 │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite (modern SPA)
#   - Backend: Managed Functions (deployed by SWA, westeurope)
#   - Authentication: None - completely open
#   - Use case: Simple EU app, automatic deployment
#   - Cost: ~$9/month (Standard tier SWA, managed functions included)
#
# Key Differences from Stack 03 (BYO):
#   - No separate function app (embedded in SWA)
#   - Region locked to westeurope (EU compliance)
#   - Automatic deployment with SWA
#   - Simpler management
#   - Same cost as BYO
#
# Usage:
#   ./stack-04-swa-typescript-managed.sh
#   CUSTOM_DOMAIN="yourdomain.com" ./stack-04-swa-typescript-managed.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   CUSTOM_DOMAIN        - Base domain for DNS (default: publiccloudexperiments.net)
#   SUBDOMAIN            - Subdomain prefix (default: managed)

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

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-managed}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-managed}"
readonly LOCATION="westeurope"  # Fixed for managed functions

# Banner
echo ""
log_info "========================================="
log_info "Stack 04: SWA TypeScript (Managed Functions)"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA"
log_info "  Backend:  Managed Functions (westeurope)"
log_info "  Auth:     None - completely public"
log_info "  Cost:     ~\$9/month (Standard tier SWA)"
log_info "  Domain:   ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "This will deploy a complete stack with:"
log_info "  1. Azure Static Web App (Standard tier)"
log_info "  2. Managed Functions (deployed by SWA)"
log_info "  3. TypeScript Vite frontend"
log_info "  4. API at /api/* route (same-origin)"
log_info ""
log_info "Key characteristics:"
log_info "  - No separate function app (managed by SWA)"
log_info "  - Region: westeurope (EU compliance)"
log_info "  - Automatic deployment process"
log_info "  - Simplest setup for EU deployments"
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
log_step "Step 1/2: Creating Azure Static Web App..."
echo ""

export RESOURCE_GROUP
export STATIC_WEB_APP_NAME
export LOCATION
export STATIC_WEB_APP_SKU="Standard"  # Required for custom domains

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

# Step 2: Deploy frontend with managed functions
log_step "Step 2/2: Deploying TypeScript Vite frontend with managed functions..."
echo ""

FRONTEND_DIR="${PROJECT_ROOT}/subnet-calculator/frontend-typescript-vite"
API_DIR="${PROJECT_ROOT}/subnet-calculator/api-fastapi-azure-function"

cd "${FRONTEND_DIR}"

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
  log_info "Installing npm dependencies..."
  npm install
fi

# Build frontend with empty API URL (use /api route)
log_info "Building production bundle (API URL: /api - relative)..."
VITE_API_URL="" npm run build

# Get deployment token
log_info "Retrieving deployment token..."
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query properties.apiKey -o tsv)

# Check if SWA CLI is installed
if ! command -v swa &>/dev/null; then
  log_warn "Azure Static Web Apps CLI not found. Installing globally..."
  npm install -g @azure/static-web-apps-cli
fi

# Deploy with managed functions
log_info "Deploying frontend and managed functions to Azure Static Web App..."
log_info "NOTE: SWA will deploy your API code to managed functions in westeurope"
log_info "This may take 3-5 minutes for initial deployment..."
echo ""

# CRITICAL: api-location points to actual API code (NOT empty string)
# This tells SWA to deploy managed functions
npx @azure/static-web-apps-cli deploy \
  --app-location dist \
  --api-location "${API_DIR}" \
  --deployment-token "${DEPLOYMENT_TOKEN}" \
  --env production

log_info "Deployment complete!"
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
log_info "  Managed Functions: Embedded in SWA (westeurope)"
log_info ""
log_info "URLs:"
log_info "  Frontend (Azure):  https://${SWA_URL}"
log_info "  API (via SWA):     https://${SWA_URL}/api/v1/health"
log_info "  API Docs:          https://${SWA_URL}/api/v1/docs"
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
log_info "  # Test API health (via SWA)"
log_info "  curl https://${SWA_URL}/api/v1/health"
log_info ""
log_info "  # Test IPv4 calculation"
log_info "  curl 'https://${SWA_URL}/api/v1/ipv4/subnet-info' \\"
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
log_info "  - Managed Functions (westeurope, SWA-controlled)"
log_info "  - No separate function app resource"
log_info "  - Same-origin API calls (/api route)"
log_info "  - No authentication - completely public"
log_info "  - Cost: ~\$9/month (Standard tier SWA)"
log_info ""
log_info "Key observations:"
log_info "  ✓ No separate function app in Portal"
log_info "  ✓ Region locked to westeurope (EU compliance)"
log_info "  ✓ Automatic deployment process"
log_info "  ✓ Same-origin benefits (no CORS)"
log_info "  ✗ Cannot deploy to uksouth (managed limitation)"
log_info ""
log_info "Compare with Stack 03 (BYO):"
log_info "  Stack 03: Separate function app, any region, manual deployment"
log_info "  Stack 04: Embedded functions, westeurope only, automatic deployment"
log_info "  Cost: Same (~\$9/month)"
log_info ""
log_info "Note: Initial deployment may take 3-5 minutes to fully propagate."
log_info "      DNS propagation may take 5-10 minutes."
log_info ""
log_info "========================================="
echo ""
