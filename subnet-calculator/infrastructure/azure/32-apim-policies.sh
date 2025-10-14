#!/usr/bin/env bash
#
# Configure Azure API Management policies
# - Applies inbound/outbound policies to API
# - Supports three authentication modes: none, subscription, jwt
# - Creates subscription for subscription mode
# - Configures rate limiting and CORS

set -euo pipefail

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

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    az group list --query "[].[name,location]" -o tsv | awk '{printf "  - %s (%s)\n", $1, $2}'
    read -r -p "Enter resource group name: " RESOURCE_GROUP
  fi
fi

# Auto-detect or prompt for APIM_NAME
if [[ -z "${APIM_NAME:-}" ]]; then
  log_info "APIM_NAME not set. Looking for APIM instances in ${RESOURCE_GROUP}..."
  APIM_COUNT=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${APIM_COUNT}" -eq 0 ]]; then
    log_error "No APIM instances found in ${RESOURCE_GROUP}"
    log_error "Run ./30-apim-instance.sh first"
    exit 1
  elif [[ "${APIM_COUNT}" -eq 1 ]]; then
    APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected APIM instance: ${APIM_NAME}"
  else
    log_warn "Multiple APIM instances found:"
    az apim list --resource-group "${RESOURCE_GROUP}" --query "[].[name]" -o tsv | awk '{printf "  - %s\n", $1}'
    read -r -p "Enter APIM instance name: " APIM_NAME
  fi
fi

# Configuration
readonly API_PATH="${API_PATH:-subnet-calc}"
readonly AUTH_MODE="${AUTH_MODE:-subscription}"  # none | subscription | jwt
readonly RATE_LIMIT="${RATE_LIMIT:-100}"  # requests per minute

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

# Apply policy to API using REST API
log_info "Applying policy to API..."

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Load and escape the policy XML
POLICY_CONTENT=$(cat "${POLICY_FILE}")
# Escape double quotes and newlines for JSON
ESCAPED_POLICY=$(echo "$POLICY_CONTENT" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

# Construct the request body
BODY="{\"properties\":{\"format\":\"rawxml\",\"value\":\"$ESCAPED_POLICY\"}}"

# Construct the REST API URL
POLICY_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/apis/${API_PATH}/policies/policy?api-version=2022-09-01-preview"

# Apply the policy using az rest
if az rest --method PUT --uri "${POLICY_URL}" --body "$BODY" --headers "Content-Type=application/json" &>/dev/null; then
  log_info "✓ Policy applied successfully"
else
  log_error "Failed to apply policy"
  exit 1
fi

# Update API subscription requirement based on auth mode
if [[ "${AUTH_MODE}" == "none" ]]; then
  log_info "Disabling subscription requirement for open access..."
  az apim api update \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --api-id "${API_PATH}" \
    --subscription-required false \
    --output none
  log_info "✓ Subscription requirement disabled"
elif [[ "${AUTH_MODE}" == "subscription" ]]; then
  log_info "Ensuring subscription requirement is enabled..."
  az apim api update \
    --resource-group "${RESOURCE_GROUP}" \
    --service-name "${APIM_NAME}" \
    --api-id "${API_PATH}" \
    --subscription-required true \
    --output none
  log_info "✓ Subscription requirement enabled"
fi

# Handle subscription key creation for subscription mode
if [[ "${AUTH_MODE}" == "subscription" ]]; then
  log_info ""
  log_info "Creating subscription for API access..."

  SUB_ID="subnet-calc-subscription"
  SUB_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/${SUB_ID}?api-version=2022-09-01-preview"

  # Check if subscription already exists
  if az rest --method GET --uri "${SUB_URL}" &>/dev/null; then
    log_info "Subscription ${SUB_ID} already exists"
  else
    # Create subscription
    SUB_BODY="{\"properties\":{\"scope\":\"/apis/${API_PATH}\",\"displayName\":\"Subnet Calculator Subscription\",\"state\":\"active\"}}"

    if az rest --method PUT --uri "${SUB_URL}" --body "$SUB_BODY" --headers "Content-Type=application/json" &>/dev/null; then
      log_info "✓ Subscription created"
    else
      log_error "Failed to create subscription"
      exit 1
    fi
  fi

  # Get subscription keys
  SECRETS_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/${SUB_ID}/listSecrets?api-version=2022-09-01-preview"

  SECRETS=$(az rest --method POST --uri "${SECRETS_URL}")
  PRIMARY_KEY=$(echo "$SECRETS" | jq -r '.primaryKey')
  SECONDARY_KEY=$(echo "$SECRETS" | jq -r '.secondaryKey')

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
