#!/usr/bin/env bash
#
# 55-add-path-based-routing.sh - Add URL Path-Based Routing to Application Gateway
#
# This script configures URL path-based routing on Application Gateway to route
# different URL paths to different backend pools. This is required for Stack 18
# where SWA and APIM are both private and accessed through the same AppGW domain.
#
# Use Case (Stack 18):
#   /* → SWA backend (static content, frontend)
#   /api/* → APIM backend (API calls)
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   APPGW_NAME="agw-swa-subnet-calc-private-endpoint" \
#   LISTENER_NAME="swa-apim-private-listener" \
#   SWA_BACKEND_POOL="swa-apim-private-backend" \
#   APIM_BACKEND_POOL="apim-backend" \
#   ./55-add-path-based-routing.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP      - Resource group name
#   APPGW_NAME          - Application Gateway name
#   LISTENER_NAME       - Listener to convert to path-based routing
#   SWA_BACKEND_POOL    - Backend pool name for SWA (default path /*)
#   APIM_BACKEND_POOL   - Backend pool name for APIM (/api/* path)
#
# Optional Environment Variables:
#   SWA_HTTP_SETTINGS     - HTTP settings for SWA (default: auto-detect)
#   APIM_HTTP_SETTINGS    - HTTP settings for APIM (default: auto-detect)
#   URL_PATH_MAP_NAME     - Path map name (default: listener-name-path-map)
#   API_PATH_RULE_NAME    - API path rule name (default: api-path-rule)
#   DEFAULT_POOL          - Default backend pool for /* (default: SWA_BACKEND_POOL)
#
# Exit Codes:
#   0 - Success (path-based routing configured)
#   1 - Error (validation failed, configuration failed)
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/application-gateway/url-route-overview

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

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

if [[ -z "${APPGW_NAME:-}" ]]; then
  log_error "APPGW_NAME environment variable is required"
  exit 1
fi

if [[ -z "${LISTENER_NAME:-}" ]]; then
  log_error "LISTENER_NAME environment variable is required"
  exit 1
fi

if [[ -z "${SWA_BACKEND_POOL:-}" ]]; then
  log_error "SWA_BACKEND_POOL environment variable is required"
  log_error "Example: SWA_BACKEND_POOL='swa-apim-private-backend' $0"
  exit 1
fi

if [[ -z "${APIM_BACKEND_POOL:-}" ]]; then
  log_error "APIM_BACKEND_POOL environment variable is required"
  log_error "Example: APIM_BACKEND_POOL='apim-backend' $0"
  exit 1
fi

# Configuration with defaults
readonly URL_PATH_MAP_NAME="${URL_PATH_MAP_NAME:-${LISTENER_NAME}-path-map}"
readonly API_PATH_RULE_NAME="${API_PATH_RULE_NAME:-api-path-rule}"
readonly DEFAULT_POOL="${DEFAULT_POOL:-${SWA_BACKEND_POOL}}"

log_info "Configuration:"
log_info "  Resource Group:   ${RESOURCE_GROUP}"
log_info "  AppGW:            ${APPGW_NAME}"
log_info "  Listener:         ${LISTENER_NAME}"
log_info "  SWA Backend:      ${SWA_BACKEND_POOL}"
log_info "  APIM Backend:     ${APIM_BACKEND_POOL}"
log_info "  URL Path Map:     ${URL_PATH_MAP_NAME}"
log_info "  API Path Rule:    ${API_PATH_RULE_NAME}"
log_info ""

# Verify AppGW exists
log_step "Verifying Application Gateway..."
if ! APPGW_STATE=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "provisioningState" -o tsv 2>/dev/null); then
  log_error "Application Gateway '${APPGW_NAME}' not found"
  exit 1
fi

if [[ "${APPGW_STATE}" != "Succeeded" ]]; then
  log_error "Application Gateway state: ${APPGW_STATE}"
  exit 1
fi

log_info "Application Gateway is ready"

# Verify listener exists
log_step "Verifying listener..."
if ! az network application-gateway http-listener show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${LISTENER_NAME}" &>/dev/null; then
  log_error "Listener '${LISTENER_NAME}' not found"
  log_error "Create listener first with script 54"
  exit 1
fi

log_info "Listener exists: ${LISTENER_NAME}"

# Verify backend pools exist
log_step "Verifying backend pools..."
for POOL in "${SWA_BACKEND_POOL}" "${APIM_BACKEND_POOL}"; do
  if ! az network application-gateway address-pool show \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${POOL}" &>/dev/null; then
    log_error "Backend pool '${POOL}' not found"
    exit 1
  fi
  log_info "Backend pool exists: ${POOL}"
done

# Auto-detect HTTP settings if not specified
log_step "Detecting HTTP settings..."

if [[ -z "${SWA_HTTP_SETTINGS:-}" ]]; then
  # Try to find HTTP settings with SWA in the name
  SWA_HTTP_SETTINGS=$(az network application-gateway http-settings list \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?contains(name, 'swa') || contains(name, 'SWA')].name | [0]" -o tsv 2>/dev/null || echo "")

  if [[ -z "${SWA_HTTP_SETTINGS}" ]]; then
    # Fallback: use first HTTP settings
    SWA_HTTP_SETTINGS=$(az network application-gateway http-settings list \
      --gateway-name "${APPGW_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
  fi

  log_info "Auto-detected SWA HTTP settings: ${SWA_HTTP_SETTINGS}"
fi

if [[ -z "${APIM_HTTP_SETTINGS:-}" ]]; then
  # Try to find HTTP settings with APIM in the name
  APIM_HTTP_SETTINGS=$(az network application-gateway http-settings list \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?contains(name, 'apim') || contains(name, 'APIM')].name | [0]" -o tsv 2>/dev/null || echo "")

  if [[ -z "${APIM_HTTP_SETTINGS}" ]]; then
    # Fallback: use SWA settings (works if both use HTTPS/443)
    APIM_HTTP_SETTINGS="${SWA_HTTP_SETTINGS}"
  fi

  log_info "Auto-detected APIM HTTP settings: ${APIM_HTTP_SETTINGS}"
fi

# Find routing rule that uses this listener
log_step "Finding routing rule..."
ROUTING_RULE=$(az network application-gateway rule list \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?httpListener.id && contains(httpListener.id, '${LISTENER_NAME}')].name | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${ROUTING_RULE}" ]]; then
  log_error "No routing rule found for listener '${LISTENER_NAME}'"
  log_error "Create a basic routing rule first with script 54"
  exit 1
fi

log_info "Found routing rule: ${ROUTING_RULE}"

# Get routing rule priority (needed for update)
ROUTING_PRIORITY=$(az network application-gateway rule show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ROUTING_RULE}" \
  --query "priority" -o tsv)

log_info "Routing rule priority: ${ROUTING_PRIORITY}"

# Check if URL path map already exists
log_step "Checking for existing URL path map..."
if az network application-gateway url-path-map show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${URL_PATH_MAP_NAME}" &>/dev/null; then
  log_warn "URL path map '${URL_PATH_MAP_NAME}' already exists"
  log_info "Skipping path map creation"
else
  # Create URL path map with default rule (/*) pointing to SWA
  log_step "Creating URL path map..."
  az network application-gateway url-path-map create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${URL_PATH_MAP_NAME}" \
    --paths "/*" \
    --address-pool "${DEFAULT_POOL}" \
    --http-settings "${SWA_HTTP_SETTINGS}" \
    --rule-name "default-path-rule" \
    --output none

  log_info "URL path map created: ${URL_PATH_MAP_NAME}"
fi

# Add path rule for /api/* → APIM
log_step "Adding API path rule..."
if az network application-gateway url-path-map rule show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --path-map-name "${URL_PATH_MAP_NAME}" \
  --name "${API_PATH_RULE_NAME}" &>/dev/null; then
  log_info "API path rule already exists"
else
  az network application-gateway url-path-map rule create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --path-map-name "${URL_PATH_MAP_NAME}" \
    --name "${API_PATH_RULE_NAME}" \
    --paths "/api/*" \
    --address-pool "${APIM_BACKEND_POOL}" \
    --http-settings "${APIM_HTTP_SETTINGS}" \
    --output none

  log_info "API path rule created: ${API_PATH_RULE_NAME}"
fi

# Update routing rule to use path-based routing
log_step "Converting routing rule to path-based routing..."
az network application-gateway rule update \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ROUTING_RULE}" \
  --rule-type PathBasedRouting \
  --url-path-map "${URL_PATH_MAP_NAME}" \
  --priority "${ROUTING_PRIORITY}" \
  --output none

log_info "Routing rule updated to path-based routing"

log_info ""
log_info "✓ Path-Based Routing Configured!"
log_info ""
log_info "========================================="
log_info "Routing Configuration"
log_info "========================================="
log_info "Listener:         ${LISTENER_NAME}"
log_info "Routing Rule:     ${ROUTING_RULE}"
log_info "URL Path Map:     ${URL_PATH_MAP_NAME}"
log_info ""
log_info "Path Rules:"
log_info "  /* (default)    → ${DEFAULT_POOL} (SWA)"
log_info "  /api/*          → ${APIM_BACKEND_POOL} (APIM)"
log_info ""
log_info "HTTP Settings:"
log_info "  SWA:  ${SWA_HTTP_SETTINGS}"
log_info "  APIM: ${APIM_HTTP_SETTINGS}"
log_info ""
log_info "Traffic Flow:"
log_info "  https://your-domain.com/         → SWA"
log_info "  https://your-domain.com/api/...  → APIM → Function"
log_info ""
