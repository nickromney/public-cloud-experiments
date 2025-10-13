#!/usr/bin/env bash
#
# Configure Azure API Management policies
# - Applies inbound/outbound policies to API
# - Supports three authentication modes: none, subscription, jwt
# - Creates subscription for subscription mode
# - Configures rate limiting and CORS

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP environment variable is required}"
readonly APIM_NAME="${APIM_NAME:?APIM_NAME environment variable is required}"
readonly API_PATH="${API_PATH:-subnet-calc}"
readonly AUTH_MODE="${AUTH_MODE:-subscription}"  # none | subscription | jwt
readonly RATE_LIMIT="${RATE_LIMIT:-100}"  # requests per minute

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory for policy files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/policies"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  APIM Name: ${APIM_NAME}"
log_info "  API Path: /${API_PATH}"
log_info "  Auth Mode: ${AUTH_MODE}"
log_info "  Rate Limit: ${RATE_LIMIT} requests/minute"

# Validate auth mode
case "${AUTH_MODE}" in
  none|subscription|jwt)
    ;;
  *)
    log_error "Invalid AUTH_MODE: ${AUTH_MODE}"
    log_error "Valid options: none, subscription, jwt"
    exit 1
    ;;
esac

# Verify APIM exists
if ! az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "APIM instance ${APIM_NAME} not found"
  log_error "Run ./30-apim-instance.sh first"
  exit 1
fi

# Verify API exists
if ! az apim api show \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${API_PATH}" &>/dev/null; then
  log_error "API ${API_PATH} not found in APIM"
  log_error "Run ./31-apim-backend.sh first"
  exit 1
fi

# Select policy file
POLICY_FILE="${POLICIES_DIR}/inbound-${AUTH_MODE}.xml"

if [[ ! -f "${POLICY_FILE}" ]]; then
  log_error "Policy file not found: ${POLICY_FILE}"
  exit 1
fi

log_info "Using policy file: $(basename "${POLICY_FILE}")"

# Warning for JWT mode in sandbox
if [[ "${AUTH_MODE}" == "jwt" ]]; then
  log_warn "⚠️  JWT authentication requires Azure Entra ID"
  log_warn "⚠️  Entra ID is NOT SUPPORTED in Pluralsight sandbox"
  log_warn "⚠️  This policy will fail in sandbox environments"
  log_warn ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted"
    exit 0
  fi
fi

# Apply policy to API
log_info "Applying policy to API..."

az apim api policy create \
  --resource-group "${RESOURCE_GROUP}" \
  --service-name "${APIM_NAME}" \
  --api-id "${API_PATH}" \
  --xml-policy "@${POLICY_FILE}" \
  --output none

log_info "✓ Policy applied successfully"

# Handle subscription key creation for subscription mode
if [[ "${AUTH_MODE}" == "subscription" ]]; then
  log_info ""
  log_info "Creating subscription for API access..."

  SUBSCRIPTION_ID="subnet-calc-subscription"

  # Check if subscription already exists
  if az apim subscription show \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --sid "${SUBSCRIPTION_ID}" &>/dev/null; then
    log_info "Subscription ${SUBSCRIPTION_ID} already exists"
  else
    # Create subscription
    az apim subscription create \
      --resource-group "${RESOURCE_GROUP}" \
      --service-name "${APIM_NAME}" \
      --sid "${SUBSCRIPTION_ID}" \
      --scope "/apis/${API_PATH}" \
      --display-name "Subnet Calculator Subscription" \
      --state active \
      --output none

    log_info "✓ Subscription created"
  fi

  # Get subscription keys
  PRIMARY_KEY=$(az apim subscription list-secrets \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --sid "${SUBSCRIPTION_ID}" \
    --query primaryKey -o tsv)

  SECONDARY_KEY=$(az apim subscription list-secrets \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --sid "${SUBSCRIPTION_ID}" \
    --query secondaryKey -o tsv)

  # Get APIM gateway URL
  APIM_GATEWAY=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query gatewayUrl -o tsv)

  log_info ""
  log_info "✓ Subscription Keys:"
  log_info "  Primary Key: ${PRIMARY_KEY}"
  log_info "  Secondary Key: ${SECONDARY_KEY}"
  log_info ""
  log_info "Test API with subscription key:"
  log_info "  curl -H \"Ocp-Apim-Subscription-Key: ${PRIMARY_KEY}\" \\"
  log_info "    ${APIM_GATEWAY}/${API_PATH}/api/v1/health"
fi

# Get APIM gateway URL for final message
APIM_GATEWAY=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query gatewayUrl -o tsv)

log_info ""
log_info "✓ APIM Policy Configuration Complete!"
log_info ""
log_info "Policy Details:"
log_info "  Mode: ${AUTH_MODE}"
log_info "  Rate Limit: ${RATE_LIMIT} requests/minute"
log_info "  API URL: ${APIM_GATEWAY}/${API_PATH}"
log_info ""

case "${AUTH_MODE}" in
  none)
    log_info "Authentication: None (open access)"
    log_info "Test API: curl ${APIM_GATEWAY}/${API_PATH}/api/v1/health"
    ;;
  subscription)
    log_info "Authentication: Subscription key required"
    log_info "  Header: Ocp-Apim-Subscription-Key"
    ;;
  jwt)
    log_info "Authentication: JWT token required"
    log_info "  Header: Authorization: Bearer <token>"
    log_warn "⚠️  Requires Entra ID configuration (not available in sandbox)"
    ;;
esac

log_info ""
log_info "Next Steps:"
log_info "  1. Deploy Function App for APIM: ./23-deploy-function-apim.sh"
log_info "  2. Deploy frontend with APIM: USE_APIM=true ./20-deploy-frontend.sh"
