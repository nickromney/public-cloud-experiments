#!/usr/bin/env bash
#
# Configure VNet integration for Azure Function App on App Service Plan
# - Enables VNet integration for outbound traffic routing
# - Validates Function is on App Service Plan (NOT Consumption)
# - Validates subnet delegation to Microsoft.Web/serverFarms
# - Sets WEBSITE_VNET_ROUTE_ALL=1 to route all traffic through VNet
# - Idempotent: checks existing integration status
# - Works in sandbox environments (pre-existing resource group)

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

# Extract resource name from Azure resource ID
# Usage: extract_resource_name "/subscriptions/.../virtualNetworks/my-vnet" "virtualNetworks"
extract_resource_name() {
  local resource_id="$1"
  local resource_type="$2"
  echo "${resource_id}" | awk -F'/' -v type="${resource_type}" '{for(i=1;i<=NF;i++) if($i==type) print $(i+1)}'
}

# Get script directory and source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/selection-utils.sh
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Parse arguments
CHECK_MODE="false"
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE="true"
fi

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Auto-detect or prompt for FUNCTION_APP_NAME
if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
  log_info "FUNCTION_APP_NAME not set. Looking for Function Apps in ${RESOURCE_GROUP}..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in ${RESOURCE_GROUP}"
    log_error "Create one first with: ./10-function-app.sh or ./13-create-function-app-on-app-service-plan.sh"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Found Function App: ${FUNCTION_APP_NAME}"
    read -r -p "Configure VNet integration for this Function? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_info "Found ${FUNC_COUNT} Function Apps in ${RESOURCE_GROUP}:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

# Auto-detect or prompt for VNET_NAME
if [[ -z "${VNET_NAME:-}" ]]; then
  VNET_COUNT=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${VNET_COUNT}" -eq 0 ]]; then
    log_error "No VNets found in ${RESOURCE_GROUP}"
    log_error "Create one first with: ./11-create-vnet-infrastructure.sh"
    exit 1
  elif [[ "${VNET_COUNT}" -eq 1 ]]; then
    VNET_NAME=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected VNet: ${VNET_NAME}"
  else
    log_info "Found ${VNET_COUNT} VNets in ${RESOURCE_GROUP}:"
    # Build array for selection
    vnet_items=()
    while IFS=$'\t' read -r name prefix; do
      vnet_items+=("${name} (${prefix})")
    done < <(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[].[name,addressSpace.addressPrefixes[0]]" -o tsv)
    VNET_NAME=$(select_from_list "Enter VNet" "${vnet_items[@]}") || exit 1
    log_info "Selected: ${VNET_NAME}"
  fi
fi

# Configuration with defaults
readonly SUBNET_NAME="${SUBNET_NAME:-snet-function-integration}"
readonly ROUTE_ALL_TRAFFIC="${ROUTE_ALL_TRAFFIC:-true}"

# Check mode - display status and exit
if [[ "${CHECK_MODE}" == "true" ]]; then
  log_info "========================================="
  log_info "VNet Integration Status Report"
  log_info "========================================="
  log_info ""
  log_info "Configuration:"
  log_info "  Resource Group: ${RESOURCE_GROUP}"
  log_info "  Function App: ${FUNCTION_APP_NAME}"
  log_info "  VNet: ${VNET_NAME}"
  log_info "  Subnet: ${SUBNET_NAME}"
  log_info ""

  # Check if function exists
  log_step "Checking Function App..."
  if ! az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    log_error "Function App ${FUNCTION_APP_NAME} not found in resource group ${RESOURCE_GROUP}"
    exit 1
  fi

  # Get function details
  FUNCTION_URL=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "defaultHostName" -o tsv)

  PLAN_ID=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "appServicePlanId" \
    -o tsv)

  if [[ -n "${PLAN_ID}" ]] && [[ "${PLAN_ID}" != "null" ]]; then
    PLAN_NAME=$(echo "${PLAN_ID}" | awk -F'/' '{print $NF}')
    PLAN_SKU=$(az appservice plan show \
      --name "${PLAN_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "sku.name" \
      -o tsv)
    PLAN_TIER=$(az appservice plan show \
      --name "${PLAN_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "sku.tier" \
      -o tsv)
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "  URL: https://${FUNCTION_URL}"
    log_info "  Plan: ${PLAN_NAME} (${PLAN_SKU} - ${PLAN_TIER})"
  else
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "  URL: https://${FUNCTION_URL}"
    log_info "  Plan: None (Consumption)"
  fi
  log_info ""

  # Check VNet integration status
  log_step "Checking VNet Integration Status..."
  INTEGRATION_LIST=$(az functionapp vnet-integration list \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    2>/dev/null || echo "[]")

  INTEGRATION_COUNT=$(echo "${INTEGRATION_LIST}" | jq -r 'length')

  if [[ "${INTEGRATION_COUNT}" -gt 0 ]]; then
    VNET_ID=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].vnetResourceId')
    SUBNET_ID=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].properties.subnetResourceId // .[0].id')
    CURRENT_VNET=$(extract_resource_name "${VNET_ID}" "virtualNetworks")
    CURRENT_SUBNET=$(extract_resource_name "${SUBNET_ID}" "subnets")
    INTEGRATION_STATUS=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].properties.status // "Unknown"')

    log_info "VNet Integration: ENABLED"
    log_info "  Status: ${INTEGRATION_STATUS}"
    log_info "  VNet: ${CURRENT_VNET}"
    log_info "  Subnet: ${CURRENT_SUBNET}"
    log_info "  VNet ID: ${VNET_ID}"
    log_info "  Subnet ID: ${SUBNET_ID}"
  else
    log_warn "VNet Integration: NOT ENABLED"
    log_info "  Status: Not integrated"
  fi
  log_info ""

  # Check WEBSITE_VNET_ROUTE_ALL setting
  log_step "Checking WEBSITE_VNET_ROUTE_ALL Setting..."
  ROUTE_ALL=$(az functionapp config appsettings list \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?name=='WEBSITE_VNET_ROUTE_ALL'].value" \
    -o tsv 2>/dev/null || echo "")

  if [[ "${ROUTE_ALL}" == "1" ]]; then
    log_info "WEBSITE_VNET_ROUTE_ALL: 1 (all traffic routed through VNet)"
  elif [[ -n "${ROUTE_ALL}" ]]; then
    log_warn "WEBSITE_VNET_ROUTE_ALL: ${ROUTE_ALL} (only RFC1918 traffic routed through VNet)"
  else
    log_warn "WEBSITE_VNET_ROUTE_ALL: not set (default behavior - RFC1918 only)"
  fi
  log_info ""

  # Check outbound IP addresses
  log_step "Checking Outbound IP Addresses..."
  OUTBOUND_IPS=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "outboundIpAddresses" \
    -o tsv 2>/dev/null || echo "")

  POSSIBLE_OUTBOUND_IPS=$(az functionapp show \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "possibleOutboundIpAddresses" \
    -o tsv 2>/dev/null || echo "")

  if [[ -n "${OUTBOUND_IPS}" ]]; then
    log_info "Current Outbound IPs:"
    echo "${OUTBOUND_IPS}" | tr ',' '\n' | while read -r ip; do
      log_info "  - ${ip}"
    done
  fi

  if [[ -n "${POSSIBLE_OUTBOUND_IPS}" ]]; then
    log_info "Possible Outbound IPs (if VNet NAT configured):"
    echo "${POSSIBLE_OUTBOUND_IPS}" | tr ',' '\n' | while read -r ip; do
      log_info "  - ${ip}"
    done
  fi
  log_info ""

  # Test function connectivity
  log_step "Testing Function Connectivity..."
  HEALTH_URL="https://${FUNCTION_URL}/api/v1/health"
  log_info "Testing endpoint: ${HEALTH_URL}"

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" --max-time 10 || echo "000")

  if [[ "${HTTP_STATUS}" == "200" ]]; then
    log_info "Function responding: ${HTTP_STATUS} OK"
  elif [[ "${HTTP_STATUS}" == "401" ]] || [[ "${HTTP_STATUS}" == "403" ]]; then
    log_warn "Function responding with auth required: ${HTTP_STATUS}"
  elif [[ "${HTTP_STATUS}" == "000" ]]; then
    log_error "Function not responding (timeout or connection error)"
  else
    log_warn "Function returned status: ${HTTP_STATUS}"
  fi
  log_info ""

  # Summary
  log_info "========================================="
  log_info "Status Summary"
  log_info "========================================="
  if [[ "${INTEGRATION_COUNT}" -gt 0 ]]; then
    log_info "VNet Integration: CONFIGURED"
    if [[ "${ROUTE_ALL}" == "1" ]]; then
      log_info "All outbound traffic routed through VNet"
    else
      log_warn "Only RFC1918 traffic routed through VNet (set WEBSITE_VNET_ROUTE_ALL=1 for all traffic)"
    fi
  else
    log_warn "VNet Integration: NOT CONFIGURED"
    log_info ""
    log_info "To enable VNet integration, run:"
    log_info "  RESOURCE_GROUP='${RESOURCE_GROUP}' \\"
    log_info "  FUNCTION_APP_NAME='${FUNCTION_APP_NAME}' \\"
    log_info "  ./14-configure-function-vnet-integration.sh"
  fi
  log_info ""

  exit 0
fi

log_info "========================================="
log_info "VNet Integration Configuration"
log_info "========================================="
log_info ""
log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  VNet: ${VNET_NAME}"
log_info "  Subnet: ${SUBNET_NAME}"
log_info "  Route All Traffic: ${ROUTE_ALL_TRAFFIC}"
log_info ""

# Step 1: Verify Function App exists
log_step "Verifying Function App exists..."
if ! az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found in resource group ${RESOURCE_GROUP}"
  log_error ""
  log_error "Available functions:"
  az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv || true
  log_error ""
  log_error "Create the function first using: ./13-create-function-app-on-app-service-plan.sh"
  exit 1
fi

# Step 2: Verify Function is on App Service Plan (not Consumption)
log_step "Verifying Function is on App Service Plan..."
PLAN_ID=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "appServicePlanId" \
  -o tsv)

if [[ -z "${PLAN_ID}" ]] || [[ "${PLAN_ID}" == "null" ]]; then
  log_error "Function App ${FUNCTION_APP_NAME} does not have an App Service Plan"
  log_error "VNet integration requires a Function on an App Service Plan (Basic, Standard, or Premium)"
  log_error ""
  log_error "Options:"
  log_error "  1. Create new function on App Service Plan: ./13-create-function-app-on-app-service-plan.sh"
  log_error "  2. Migrate existing Consumption function: ./13-migrate-function-to-app-service-plan.sh"
  exit 1
fi

PLAN_NAME=$(echo "${PLAN_ID}" | awk -F'/' '{print $NF}')
PLAN_SKU=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.name" \
  -o tsv)

PLAN_TIER=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.tier" \
  -o tsv)

log_info "Function is on App Service Plan: ${PLAN_NAME} (${PLAN_SKU} - ${PLAN_TIER})"

# Check if this is actually a Consumption plan
if [[ "${PLAN_TIER,,}" == *"dynamic"* ]] || [[ "${PLAN_SKU,,}" == "y1" ]]; then
  log_error "Function App ${FUNCTION_APP_NAME} is on a Consumption plan"
  log_error "VNet integration is NOT supported on Consumption plans"
  log_error ""
  log_error "You must migrate to an App Service Plan (Basic, Standard, or Premium)"
  log_error "Run: ./13-migrate-function-to-app-service-plan.sh"
  exit 1
fi

# Step 3: Get Function location
FUNCTION_LOCATION=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "location" \
  -o tsv)

log_info "Function location: ${FUNCTION_LOCATION}"

# Step 4: Verify VNet exists
log_step "Verifying VNet exists..."
if ! az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "VNet ${VNET_NAME} not found in resource group ${RESOURCE_GROUP}"
  log_error ""
  log_error "Create the VNet first using: ./11-create-vnet-infrastructure.sh"
  exit 1
fi

# Get VNet location
VNET_LOCATION=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "location" \
  -o tsv)

log_info "VNet ${VNET_NAME} exists in location: ${VNET_LOCATION}"

# Step 5: Verify Function and VNet are in same region
log_step "Verifying Function and VNet are in same region..."
# Normalize location names (remove spaces, lowercase) for comparison
FUNCTION_LOCATION_NORMALIZED=$(echo "${FUNCTION_LOCATION}" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
VNET_LOCATION_NORMALIZED=$(echo "${VNET_LOCATION}" | tr -d ' ' | tr '[:upper:]' '[:lower:]')

if [[ "${FUNCTION_LOCATION_NORMALIZED}" != "${VNET_LOCATION_NORMALIZED}" ]]; then
  log_error "Function App and VNet must be in the same region"
  log_error "  Function: ${FUNCTION_LOCATION}"
  log_error "  VNet: ${VNET_LOCATION}"
  log_error ""
  log_error "Options:"
  log_error "  1. Create VNet in ${FUNCTION_LOCATION}: LOCATION=${FUNCTION_LOCATION} ./11-create-vnet-infrastructure.sh"
  log_error "  2. Recreate Function in ${VNET_LOCATION}: LOCATION=${VNET_LOCATION} ./13-create-function-app-on-app-service-plan.sh"
  exit 1
fi

log_info "Regions match: ${FUNCTION_LOCATION} / ${VNET_LOCATION}"

# Step 6: Verify subnet exists
log_step "Verifying subnet exists..."
if ! az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Subnet ${SUBNET_NAME} not found in VNet ${VNET_NAME}"
  log_error ""
  log_error "Create the subnet first using: ./11-create-vnet-infrastructure.sh"
  exit 1
fi

# Get subnet details and resource ID
SUBNET_PREFIX=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "addressPrefix" \
  -o tsv)

SUBNET_ID=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "id" \
  -o tsv)

log_info "Subnet ${SUBNET_NAME} exists with prefix: ${SUBNET_PREFIX}"

# Step 7: Verify subnet delegation
log_step "Verifying subnet delegation..."
DELEGATION=$(az network vnet subnet show \
  --name "${SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "delegations[0].serviceName" \
  -o tsv 2>/dev/null || echo "")

if [[ "${DELEGATION}" != "Microsoft.Web/serverFarms" ]]; then
  log_error "Subnet ${SUBNET_NAME} is not delegated to Microsoft.Web/serverFarms"
  log_error "  Current delegation: ${DELEGATION:-none}"
  log_error "  Required delegation: Microsoft.Web/serverFarms"
  log_error ""
  log_error "Fix the delegation by running: ./11-create-vnet-infrastructure.sh"
  log_error "Or manually delegate:"
  log_error "  az network vnet subnet update \\"
  log_error "    --name ${SUBNET_NAME} \\"
  log_error "    --vnet-name ${VNET_NAME} \\"
  log_error "    --resource-group ${RESOURCE_GROUP} \\"
  log_error "    --delegations Microsoft.Web/serverFarms"
  exit 1
fi

log_info "Subnet delegation verified: Microsoft.Web/serverFarms"

# Step 8: Check current VNet integration status
log_step "Checking current VNet integration status..."
INTEGRATION_LIST=$(az functionapp vnet-integration list \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  2>/dev/null || echo "[]")

INTEGRATION_COUNT=$(echo "${INTEGRATION_LIST}" | jq -r 'length')

if [[ "${INTEGRATION_COUNT}" -gt 0 ]]; then
  # Extract VNet and Subnet from resource IDs
  CURRENT_VNET_ID=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].vnetResourceId')
  CURRENT_SUBNET_ID=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].properties.subnetResourceId // .[0].id')
  CURRENT_VNET=$(extract_resource_name "${CURRENT_VNET_ID}" "virtualNetworks")
  CURRENT_SUBNET=$(extract_resource_name "${CURRENT_SUBNET_ID}" "subnets")
  INTEGRATION_STATUS=$(echo "${INTEGRATION_LIST}" | jq -r '.[0].properties.status // "Unknown"')

  log_info "Current VNet integration status: ${INTEGRATION_STATUS}"
  log_info "  VNet: ${CURRENT_VNET}"
  log_info "  Subnet: ${CURRENT_SUBNET}"

  if [[ "${CURRENT_SUBNET}" == "${SUBNET_NAME}" ]] && [[ "${CURRENT_VNET}" == "${VNET_NAME}" ]]; then
    log_info ""
    log_info "VNet integration already configured for correct VNet/subnet"
    log_info "Skipping integration add (idempotent)"
    SKIP_INTEGRATION="true"
  else
    log_warn "VNet integration exists but points to different VNet/subnet"
    log_warn "  Expected: ${VNET_NAME}/${SUBNET_NAME}"
    log_warn "  Current: ${CURRENT_VNET}/${CURRENT_SUBNET}"
    log_warn ""
    log_warn "Removing old integration before adding new one..."

    az functionapp vnet-integration remove \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --output none

    log_info "Old integration removed"
    SKIP_INTEGRATION="false"
  fi
else
  log_info "Current status: Not integrated"
  SKIP_INTEGRATION="false"
fi

log_info ""

# Step 9: Enable VNet integration (if needed)
if [[ "${SKIP_INTEGRATION}" != "true" ]]; then
  log_step "Enabling VNet integration..."
  log_info "Connecting to ${VNET_NAME}/${SUBNET_NAME}..."
  log_info "Using subnet resource ID: ${SUBNET_ID}"

  az functionapp vnet-integration add \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet "${VNET_NAME}" \
    --subnet "${SUBNET_ID}" \
    --output none

  log_info "VNet integration added successfully"

  # Wait a few seconds for integration to initialize
  log_info "Waiting for integration to initialize..."
  sleep 5
fi

# Step 10: Configure route-all traffic setting
if [[ "${ROUTE_ALL_TRAFFIC,,}" == "true" ]]; then
  log_step "Configuring WEBSITE_VNET_ROUTE_ALL setting..."

  # Check current setting
  CURRENT_ROUTE_ALL=$(az functionapp config appsettings list \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?name=='WEBSITE_VNET_ROUTE_ALL'].value" \
    -o tsv 2>/dev/null || echo "")

  if [[ "${CURRENT_ROUTE_ALL}" == "1" ]]; then
    log_info "WEBSITE_VNET_ROUTE_ALL already set to 1"
  else
    log_info "Setting WEBSITE_VNET_ROUTE_ALL=1 (routes ALL traffic through VNet)..."

    az functionapp config appsettings set \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --settings WEBSITE_VNET_ROUTE_ALL=1 \
      --output none

    log_info "WEBSITE_VNET_ROUTE_ALL set successfully"
  fi
fi

log_info ""

# Step 11: Verify integration status
log_step "Verifying integration status..."
FINAL_INTEGRATION=$(az functionapp vnet-integration list \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  2>/dev/null)

FINAL_STATUS=$(echo "${FINAL_INTEGRATION}" | jq -r '.[0].properties.status // "Unknown"')
FINAL_VNET_ID=$(echo "${FINAL_INTEGRATION}" | jq -r '.[0].vnetResourceId // "Unknown"')
FINAL_SUBNET_ID=$(echo "${FINAL_INTEGRATION}" | jq -r '.[0].id // "Unknown"')

log_info "Integration status: ${FINAL_STATUS}"

if [[ "${FINAL_STATUS}" != "Unknown" ]]; then
  log_info "  VNet ID: ${FINAL_VNET_ID}"
  log_info "  Subnet ID: ${FINAL_SUBNET_ID}"
fi

# Step 12: Verify WEBSITE_VNET_ROUTE_ALL setting
FINAL_ROUTE_ALL=$(az functionapp config appsettings list \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?name=='WEBSITE_VNET_ROUTE_ALL'].value" \
  -o tsv)

log_info "  WEBSITE_VNET_ROUTE_ALL: ${FINAL_ROUTE_ALL:-not set}"

# Step 13: Test Function still responds
log_step "Testing Function still responds..."
HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostName" -o tsv)

FUNCTION_URL="https://${HOSTNAME}/api/v1/health"

log_info "Testing endpoint: ${FUNCTION_URL}"

# Wait a bit for the function to be ready after VNet changes
sleep 5

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${FUNCTION_URL}" --max-time 30 || echo "000")

if [[ "${HTTP_STATUS}" == "200" ]]; then
  log_info "Function app responding: ${HTTP_STATUS} OK"
elif [[ "${HTTP_STATUS}" == "401" ]] || [[ "${HTTP_STATUS}" == "403" ]]; then
  log_warn "Function app responding but requires authentication: ${HTTP_STATUS}"
  log_warn "This is normal if auth is enabled"
elif [[ "${HTTP_STATUS}" == "000" ]]; then
  log_warn "Function app not responding (timeout or connection error)"
  log_warn "The function may still be initializing after VNet integration"
  log_warn "Try testing again in a few minutes"
else
  log_warn "Function app returned unexpected status: ${HTTP_STATUS}"
  log_warn "The function may still be initializing after VNet integration"
fi

# Output results
log_info ""
log_info "========================================="
log_info "VNet Integration Configured Successfully!"
log_info "========================================="
log_info ""
log_info "Function App: ${FUNCTION_APP_NAME}"
log_info "  Plan: ${PLAN_NAME} (${PLAN_SKU} - ${PLAN_TIER})"
log_info "  URL: https://${HOSTNAME}"
log_info ""
log_info "VNet Integration:"
log_info "  Status: ${FINAL_STATUS}"
log_info "  VNet: ${VNET_NAME}"
log_info "  Subnet: ${SUBNET_NAME} (${SUBNET_PREFIX})"
log_info "  Route All Traffic: ${FINAL_ROUTE_ALL:-not set}"
log_info ""
log_info "Configuration Summary:"
log_info "  - All outbound traffic routes through VNet"
log_info "  - Function can access private resources in VNet"
log_info "  - Subnet delegated to Microsoft.Web/serverFarms"
log_info ""
log_info "Next steps:"
log_info "  1. Test function still works:"
log_info "     curl ${FUNCTION_URL}"
log_info ""
log_info "  2. Test access to private resources (if any):"
log_info "     - Database connections"
log_info "     - Storage account private endpoints"
log_info "     - Other VNet resources"
log_info ""
log_info "  3. Deploy or update function code if needed:"
log_info "     ./21-deploy-function.sh"
log_info ""
log_info "To verify integration status:"
log_info "  az functionapp vnet-integration list \\"
log_info "    --name ${FUNCTION_APP_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP} \\"
log_info "    --query \"[].{vnet:vnetResourceId, subnet:name, status:properties.status}\" \\"
log_info "    -o table"
log_info ""
