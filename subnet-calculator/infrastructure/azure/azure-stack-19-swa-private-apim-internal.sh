#!/usr/bin/env bash
#
# azure-stack-19-swa-private-apim-internal.sh - Deploy Stack 19: Private SWA + APIM Internal + Function JWT
#
# Architecture:
#   ┌─────────────────────────────────────┐
#   │ User → Internet                     │
#   └──────────────┬──────────────────────┘
#                  │
#   ┌──────────────▼──────────────────────┐
#   │ Application Gateway                 │
#   │ - Path-based routing                │
#   │   • /* → SWA backend                │
#   │   • /api/* → APIM backend           │
#   └────┬────────────────────┬───────────┘
#        │                    │
#        │ SWA PE             │ APIM Private IP
#   ┌────▼────────────┐  ┌───▼──────────────────┐
#   │ Static Web App  │  │ APIM (Internal VNet) │
#   │ (Private EP)    │  │ - IP-based auth      │
#   │ - Entra ID      │  │ - JWT forwarding     │
#   └─────────────────┘  └───┬──────────────────┘
#                            │ Private VNet routing
#                        ┌───▼──────────────────┐
#                        │ Function App         │
#                        │ - Private endpoint   │
#                        │ - JWT authentication │
#                        └──────────────────────┘
#
# Components:
#   - Frontend: TypeScript Vite with Entra ID
#   - Routing: Application Gateway with path-based routing
#   - API Gateway: APIM in Internal VNet mode (private IP: 10.201.0.4)
#   - Backend: Function App with JWT authentication
#   - Authentication: Entra ID on SWA, JWT on Function App
#   - Networking: All private endpoints, VNet peering
#   - Security: Maximum isolation - all components private
#   - Use case: Enterprise scenarios, compliance requirements
#
# Key Security Features:
#   - AppGW provides public endpoint, routes internally
#   - APIM validates requests (skips subscription key for AppGW IPs)
#   - APIM forwards JWT tokens to Function App
#   - Function App validates JWT tokens
#   - All network traffic stays private after AppGW
#
# Prerequisites (from Stack 16):
#   - VNet: vnet-subnet-calc-private (10.100.0.0/24)
#   - AppGW: agw-swa-subnet-calc-private-endpoint
#   - Function: func-subnet-calc-private-endpoint (with private endpoint)
#   - SWA: swa-subnet-calc-private-endpoint (with private endpoint)
#   - VNet Peering: vnet-subnet-calc-private ↔ vnet-subnet-calc-apim-internal
#   - APIM: apim-subnet-calc-05845 (Internal mode, 10.201.0.4)
#
# Usage:
#   ./azure-stack-19-swa-private-apim-internal.sh
#
# Environment variables (optional):
#   RESOURCE_GROUP           - Azure resource group (default: rg-subnet-calc)
#   FUNCTION_APP_NAME        - Function App name (default: func-subnet-calc-private-endpoint)
#   APIM_NAME                - APIM instance name (default: apim-subnet-calc-05845)
#   APIM_API_ID              - APIM API ID (default: func-subnet-calc-private-endpoint)
#   STATIC_WEB_APP_NAME      - SWA name (default: swa-subnet-calc-private-endpoint)
#   APPGW_NAME               - AppGW name (default: agw-swa-subnet-calc-private-endpoint)

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

# Configuration with defaults
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc-private-endpoint}"
readonly APIM_NAME="${APIM_NAME:-apim-subnet-calc-05845}"
readonly APIM_API_ID="${APIM_API_ID:-func-subnet-calc-private-endpoint}"
readonly APIM_API_PATH="func-private-endpoint"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc-private-endpoint}"
readonly APPGW_NAME="${APPGW_NAME:-agw-swa-subnet-calc-private-endpoint}"
readonly APIM_PRIVATE_IP="10.201.0.4"
readonly APIM_GATEWAY_HOST="apim-subnet-calc-05845.azure-api.net"

# Backend pool and HTTP settings names
readonly SWA_BACKEND_POOL="appGatewayBackendPool"
readonly SWA_HTTP_SETTINGS="appGatewayBackendHttpSettings"
readonly APIM_BACKEND_POOL="apim-backend-pool"
readonly APIM_HTTP_SETTINGS="apim-http-settings"

# Banner
echo ""
log_info "========================================================="
log_info "Stack 19: Private SWA + APIM Internal + Function JWT"
log_info "========================================================="
log_info ""
log_info "Architecture:"
log_info "  AppGW (path-based) → SWA (PE) + APIM (Internal) → Function (PE, JWT)"
log_info ""
log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Function App:   ${FUNCTION_APP_NAME}"
log_info "  APIM Instance:  ${APIM_NAME} (${APIM_PRIVATE_IP})"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  App Gateway:    ${APPGW_NAME}"
log_info ""

# Check prerequisites
log_step "Checking prerequisites..."

if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Verify resources exist
log_info "Verifying prerequisite resources..."

if ! az webapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App '${FUNCTION_APP_NAME}' not found. Run azure-stack-16 first."
  exit 1
fi

if ! az apim show --name "${APIM_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "APIM '${APIM_NAME}' not found. Ensure APIM is deployed."
  exit 1
fi

if ! az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Static Web App '${STATIC_WEB_APP_NAME}' not found. Run azure-stack-16 first."
  exit 1
fi

if ! az network application-gateway show --name "${APPGW_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Application Gateway '${APPGW_NAME}' not found. Run azure-stack-16 first."
  exit 1
fi

log_info "✓ All prerequisite resources found"

# Step 1: Configure Function App JWT Authentication
log_step "Step 1: Configure Function App JWT Authentication"
echo ""
log_info "Configuring JWT authentication for ${FUNCTION_APP_NAME}..."

JWT_SECRET=$(openssl rand -base64 32)
log_info "Generated JWT secret"

az functionapp config appsettings set \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings AUTH_METHOD=jwt JWT_SECRET="${JWT_SECRET}" \
  --output table

log_info "✓ Function App configured with JWT authentication"
echo ""

# Step 2: Configure APIM Backend API
log_step "Step 2: Configure APIM Backend API"
echo ""
log_info "Configuring APIM backend with path /${APIM_API_PATH}..."

# Update API path to unique value (not /api to avoid conflicts)
az apim api update \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${APIM_API_ID}" \
  --path "${APIM_API_PATH}" \
  --output none

# Set backend service URL to Function App
FUNC_HOSTNAME=$(az webapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

az apim api update \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${APIM_API_ID}" \
  --service-url "https://${FUNC_HOSTNAME}" \
  --output none

log_info "✓ APIM backend configured"
echo ""

# Step 3: Apply APIM Policy (IP-based auth, JWT forwarding)
log_step "Step 3: Apply APIM Policy"
echo ""
log_info "Applying APIM policy with IP-based auth and JWT forwarding..."

# Policy file: policies/inbound-appgw-jwt.xml
# Features:
# - Skip subscription key validation for requests from AppGW (10.100.0.0/24)
# - Forward JWT Authorization header to Function App
# - Rate limiting: 100 requests/minute per IP
# - CORS enabled for frontend access

POLICY_FILE="${SCRIPT_DIR}/policies/inbound-appgw-jwt.xml"

if [[ ! -f "${POLICY_FILE}" ]]; then
  log_error "Policy file not found: ${POLICY_FILE}"
  exit 1
fi

SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

az rest --method put \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/apis/${APIM_API_ID}/policies/policy?api-version=2022-08-01" \
  --body "{\"properties\":{\"format\":\"rawxml\",\"value\":\"$(sed 's/"/\\"/g' "${POLICY_FILE}" | tr -d '\n')\"}}" \
  --output none

log_info "✓ APIM policy applied"
echo ""

# Step 4: Configure Application Gateway Path-Based Routing
log_step "Step 4: Configure Application Gateway Path-Based Routing"
echo ""
log_info "Configuring Application Gateway for path-based routing..."

# Create APIM backend pool
log_info "Creating APIM backend pool..."
az network application-gateway address-pool create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${APIM_BACKEND_POOL}" \
  --servers "${APIM_PRIVATE_IP}" \
  --output none 2>/dev/null || log_warn "Backend pool already exists, continuing..."

# Create APIM HTTP settings
log_info "Creating APIM HTTP settings..."
az network application-gateway http-settings create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${APIM_HTTP_SETTINGS}" \
  --port 443 \
  --protocol Https \
  --cookie-based-affinity Disabled \
  --timeout 30 \
  --host-name "${APIM_GATEWAY_HOST}" \
  --output none 2>/dev/null || log_warn "HTTP settings already exist, continuing..."

# Create URL path map with default route to SWA
log_info "Creating URL path map for path-based routing..."
az network application-gateway url-path-map create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "path-map-swa-apim" \
  --paths "/*" \
  --address-pool "${SWA_BACKEND_POOL}" \
  --http-settings "${SWA_HTTP_SETTINGS}" \
  --default-address-pool "${SWA_BACKEND_POOL}" \
  --default-http-settings "${SWA_HTTP_SETTINGS}" \
  --output none 2>/dev/null || log_warn "URL path map already exists, continuing..."

# Add path rule for /api/* to route to APIM
log_info "Adding /api/* path rule for APIM routing..."
az network application-gateway url-path-map rule create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --path-map-name "path-map-swa-apim" \
  --name "api-path-rule" \
  --paths "/api/*" \
  --address-pool "${APIM_BACKEND_POOL}" \
  --http-settings "${APIM_HTTP_SETTINGS}" \
  --output none 2>/dev/null || log_warn "Path rule already exists, continuing..."

# Update routing rule to use path-based routing
log_info "Updating routing rule to use path-based routing..."
az network application-gateway rule update \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "rule1" \
  --rule-type PathBasedRouting \
  --url-path-map "path-map-swa-apim" \
  --output none

log_info "✓ Application Gateway path-based routing configured"
echo ""

# Step 5: Deploy Frontend
log_step "Step 5: Deploy Frontend"
echo ""
log_info "Deploying TypeScript frontend to ${STATIC_WEB_APP_NAME}..."
log_info "Frontend will use relative /api URLs (proxied by AppGW to APIM)"

# Use the 20-deploy-frontend.sh script
"${SCRIPT_DIR}/20-deploy-frontend.sh" \
  RESOURCE_GROUP="${RESOURCE_GROUP}" \
  STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME}" \
  FRONTEND="typescript" || {
  log_error "Frontend deployment failed"
  exit 1
}

log_info "✓ Frontend deployed"
echo ""

# Summary
log_step "Deployment Complete!"
echo ""
log_info "========================================================="
log_info "Stack 19 Configuration Summary"
log_info "========================================================="
log_info ""
log_info "Routing Architecture:"
log_info "  1. Client requests https://your-domain.com/"
log_info "     → AppGW routes /* to SWA (private endpoint)"
log_info ""
log_info "  2. Client requests https://your-domain.com/api/v1/health"
log_info "     → AppGW routes /api/* to APIM (${APIM_PRIVATE_IP})"
log_info "     → APIM validates (skips subscription key for AppGW IPs)"
log_info "     → APIM forwards to Function App with JWT token"
log_info "     → Function App validates JWT and responds"
log_info ""
log_info "Security Configuration:"
log_info "  ✓ Function App: JWT authentication enabled"
log_info "  ✓ APIM: IP-based auth (trusts AppGW subnet 10.100.0.0/24)"
log_info "  ✓ APIM: Forwards Authorization header to Function"
log_info "  ✓ AppGW: Path-based routing (/* → SWA, /api/* → APIM)"
log_info "  ✓ All traffic private after AppGW entry point"
log_info ""
log_info "Next Steps:"
log_info "  1. Test SWA frontend access through custom domain"
log_info "  2. Test API calls through /api/v1/health"
log_info "  3. Monitor APIM analytics for request patterns"
log_info "  4. Compare performance with other stacks using timing metrics"
log_info ""
log_info "Test Commands:"
log_info "  # Health check through APIM"
log_info "  curl https://your-custom-domain.com/api/v1/health"
log_info ""
log_info "  # Subnet calculation through APIM"
log_info "  curl -X POST https://your-custom-domain.com/api/v1/ipv4/validate \\"
log_info "    -H 'Content-Type: application/json' \\"
log_info "    -d '{\"address\":\"192.168.1.0/24\"}'"
log_info ""
log_info "========================================================="
