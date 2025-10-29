#!/usr/bin/env bash
#
# azure-stack-14-swa-noauth-jwt.sh - Deploy Stack 1: Public SWA + JWT Auth Function
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ User → Public Internet              │
#   └──────────────┬──────────────────────┘
#                  │
#   ┌──────────────▼──────────────────────┐
#   │ Azure Static Web App (Free/Std)     │
#   │ - TypeScript Vite SPA               │
#   │ - NO authentication on SWA          │
#   │ - Calls Function via public URL     │
#   └──────────────┬──────────────────────┘
#                  │ HTTPS (public internet)
#   ┌──────────────▼──────────────────────┐
#   │ Azure Function App (Consumption)    │
#   │ - Public endpoint                   │
#   │ - JWT authentication (Bearer token) │
#   │ - Custom domain enabled             │
#   └─────────────────────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with JWT auth (credentials in frontend)
#   - Backend: Function App with JWT validation
#   - Authentication: Frontend enforces JWT, backend validates tokens
#   - Security: JWT credentials embedded in frontend build
#   - Use case: Public APIs, demos, teaching JWT patterns
#   - Cost: ~$0-9/month (Consumption + SWA Free/Standard)
#
# Key Characteristics:
#   - Both SWA and Function have public URLs
#   - Function App accessible at custom domain
#   - JWT credentials visible in browser (not suitable for production secrets)
#   - CORS configured on Function App
#   - Simple architecture for teaching JWT authentication
#
# Custom Domains:
#   - SWA: static-swa-no-auth.publiccloudexperiments.net
#   - Function: subnet-calc-fa-jwt-auth.publiccloudexperiments.net
#
# Usage:
#   ./azure-stack-14-swa-noauth-jwt.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP       - Azure resource group (auto-detected if not set)
#   LOCATION             - Azure region (default: uksouth)
#   SWA_CUSTOM_DOMAIN    - SWA custom domain (default: static-swa-no-auth.publiccloudexperiments.net)
#   FUNC_CUSTOM_DOMAIN   - Function custom domain (default: subnet-calc-fa-jwt-auth.publiccloudexperiments.net)
#   JWT_SECRET_KEY       - JWT secret (default: auto-generated)
#   JWT_USERNAME         - Test username (default: demo)
#   JWT_PASSWORD         - Test password (default: password123)

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
readonly SWA_CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN:-static-swa-no-auth.publiccloudexperiments.net}"
readonly FUNC_CUSTOM_DOMAIN="${FUNC_CUSTOM_DOMAIN:-subnet-calc-fa-jwt-auth.publiccloudexperiments.net}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-noauth}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-jwt}"
readonly STATIC_WEB_APP_SKU="${STATIC_WEB_APP_SKU:-Standard}"  # Standard required for custom domains

# JWT Configuration
readonly JWT_SECRET_KEY="${JWT_SECRET_KEY:-$(openssl rand -base64 32)}"
readonly JWT_USERNAME="${JWT_USERNAME:-demo}"
readonly JWT_PASSWORD="${JWT_PASSWORD:-password123}"

# Map region to SWA-compatible region
REQUESTED_LOCATION="${LOCATION:-uksouth}"
SWA_LOCATION=$(map_swa_region "${REQUESTED_LOCATION}")
LOCATION="${REQUESTED_LOCATION}"  # Function App uses requested region (not readonly - will be temporarily overridden for SWA)
readonly SWA_LOCATION  # SWA uses mapped region

# Banner
echo ""
log_info "========================================="
log_info "Stack 1: Public SWA + JWT Auth Function"
log_info "========================================="
log_info ""
log_info "Architecture:"
log_info "  Frontend: TypeScript Vite SPA (no SWA auth)"
log_info "  Backend:  Function App (public, JWT auth)"
log_info "  Auth:     Frontend enforces JWT credentials"
log_info "  Security: JWT validation on backend"
log_info "  Cost:     ~\$9/month (Consumption + SWA Standard)"
log_info "  SWA Domain:  ${SWA_CUSTOM_DOMAIN}"
log_info "  Func Domain: ${FUNC_CUSTOM_DOMAIN}"
log_info "  Function Region: ${LOCATION}"
log_info "  SWA Region:      ${SWA_LOCATION}"
log_info ""
log_info "Key characteristics:"
log_info "  ✓ Both endpoints publicly accessible"
log_info "  ✓ JWT credentials in frontend build"
log_info "  ✓ Good for demos and teaching"
log_info "  ✗ Not suitable for sensitive data"
log_info ""

# Check prerequisites
log_step "Checking prerequisites..."
command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }
command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
command -v npm &>/dev/null || { log_error "npm not found"; exit 1; }
command -v openssl &>/dev/null || { log_error "openssl not found"; exit 1; }
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

# Generate Argon2 hash for password
log_info "Generating Argon2 password hash..."
PYTHON_CMD="from pwdlib import PasswordHash; ph = PasswordHash.recommended(); print(ph.hash('${JWT_PASSWORD}'))"

# Try with uv first (preferred), fall back to system python
JWT_PASSWORD_HASH=$(uv run --with 'pwdlib[argon2]' python -c "${PYTHON_CMD}" 2>/dev/null || python3 -c "${PYTHON_CMD}" 2>/dev/null || echo "")

if [[ -z "${JWT_PASSWORD_HASH}" ]]; then
  log_error "Failed to generate password hash"
  log_error "Ensure pwdlib[argon2] is available via uv or system python"
  exit 1
fi

readonly JWT_TEST_USERS="{\"${JWT_USERNAME}\": \"${JWT_PASSWORD_HASH}\"}"
log_info "Password hash generated"
echo ""

# Step 1: Create Function App
log_step "Step 1/6: Creating Function App..."
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

log_info "Configuring Function App settings for JWT auth..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings \
    AUTH_METHOD=jwt \
    JWT_SECRET_KEY="${JWT_SECRET_KEY}" \
    JWT_ALGORITHM=HS256 \
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30 \
    JWT_TEST_USERS="${JWT_TEST_USERS}" \
    CORS_ORIGINS="https://${SWA_CUSTOM_DOMAIN}" \
  --output none

log_info "Function App configured with JWT auth"
echo ""

# Step 2: Deploy Function API
log_step "Step 2/6: Deploying Function API..."
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
  export DISABLE_AUTH=false  # Enable JWT auth

  "${SCRIPT_DIR}/22-deploy-function-zip.sh"

  log_info "Function App deployed"
  sleep 30
fi
echo ""

# Step 3: Create Static Web App
log_step "Step 3/6: Creating Azure Static Web App..."
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

# Step 4: Deploy Frontend
log_step "Step 4/6: Deploying frontend with JWT auth..."
echo ""

log_info "Building and deploying frontend with JWT auth enabled..."
log_info "  API URL: https://${FUNC_CUSTOM_DOMAIN}"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"

export FRONTEND=typescript
export SWA_AUTH_ENABLED=false  # No SWA platform auth (Entra ID)
export VITE_AUTH_ENABLED=true  # Enable JWT auth in frontend code
export VITE_API_URL="https://${FUNC_CUSTOM_DOMAIN}"
export VITE_JWT_USERNAME="${JWT_USERNAME}"
export VITE_JWT_PASSWORD="${JWT_PASSWORD}"
export STATIC_WEB_APP_NAME
export RESOURCE_GROUP

"${SCRIPT_DIR}/20-deploy-frontend.sh"

log_info "Frontend deployed"
echo ""

# Step 5: Configure SWA Custom Domain
log_step "Step 5/6: Configuring SWA custom domain..."
echo ""

log_info "Custom domain: ${SWA_CUSTOM_DOMAIN}"
log_info "SWA hostname: ${SWA_URL}"
log_info ""
log_info "The script will now:"
log_info "  1. Add the custom domain to Azure (generates validation token)"
log_info "  2. Display the TXT record for domain validation"
log_info "  3. Display the CNAME record for traffic routing"
log_info "  4. Wait for you to configure DNS"
log_info ""

export CUSTOM_DOMAIN="${SWA_CUSTOM_DOMAIN}"
"${SCRIPT_DIR}/41-configure-custom-domain-swa.sh"

log_info "SWA custom domain configured"
echo ""

# Step 6: Configure Function Custom Domain
log_step "Step 6/6: Configuring Function App custom domain..."
echo ""

FUNC_DEFAULT_HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

# Validate hostname was retrieved
if [[ -z "${FUNC_DEFAULT_HOSTNAME}" ]]; then
  log_error "Failed to retrieve Function App hostname"
  log_error "Function App: ${FUNCTION_APP_NAME}"
  log_error "Resource Group: ${RESOURCE_GROUP}"
  exit 1
fi

# Get custom domain verification ID for TXT record
VERIFICATION_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "customDomainVerificationId" -o tsv)

log_info "Custom domain: ${FUNC_CUSTOM_DOMAIN}"
log_info "Target hostname: ${FUNC_DEFAULT_HOSTNAME}"
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
log_info "Stack 1 Deployment Complete!"
log_info "========================================="
log_info ""
log_info "URLs:"
log_info "  SWA:      https://${SWA_CUSTOM_DOMAIN}"
log_info "  Function: https://${FUNC_CUSTOM_DOMAIN}"
log_info ""
log_info "Authentication:"
log_info "  Type:     JWT (Bearer token)"
log_info "  Username: ${JWT_USERNAME}"
log_info "  Password: ${JWT_PASSWORD}"
log_info ""
log_info "Test the deployment:"
log_info "  1. Visit https://${SWA_CUSTOM_DOMAIN}"
log_info "  2. Enter credentials when prompted"
log_info "  3. Verify API calls work"
log_info ""
log_info "API Documentation:"
log_info "  https://${FUNC_CUSTOM_DOMAIN}/api/v1/docs"
log_info ""
log_warn "Note: JWT credentials are embedded in the frontend build"
log_warn "      This is suitable for demos but not production secrets"
log_info ""
