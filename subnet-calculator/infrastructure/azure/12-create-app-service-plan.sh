#!/usr/bin/env bash
#
# Create Azure App Service Plan for subnet calculator Function App
# - B1 SKU (Basic tier) by default - supports VNet integration
# - Linux OS required for Python Functions
# - Idempotent: checks if plan exists with same SKU
# - If exists with different SKU: warns and exits (no auto-upgrade)
# - Calculates and displays cost estimates
# - Works in sandbox environments (pre-existing resource group)

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Source selection utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# SKU cost mapping (per hour in USD)
get_sku_cost() {
  local sku="$1"
  case "${sku^^}" in
    B1) echo "0.018" ;;
    B2) echo "0.036" ;;
    B3) echo "0.072" ;;
    S1) echo "0.10" ;;
    S2) echo "0.20" ;;
    S3) echo "0.40" ;;
    P1V2) echo "0.20" ;;
    P2V2) echo "0.40" ;;
    P3V2) echo "0.80" ;;
    P0V3) echo "0.194" ;;  # $0.194/hour * 730 hours = ~$142/month
    P1V3) echo "0.388" ;;
    P2V3) echo "0.776" ;;
    P3V3) echo "1.552" ;;
    *) echo "0.00" ;;
  esac
}

# SKU specifications
get_sku_specs() {
  local sku="$1"
  case "${sku^^}" in
    B1) echo "1 vCPU, 1.75 GB RAM" ;;
    B2) echo "2 vCPU, 3.5 GB RAM" ;;
    B3) echo "4 vCPU, 7 GB RAM" ;;
    S1) echo "1 vCPU, 1.75 GB RAM" ;;
    S2) echo "2 vCPU, 3.5 GB RAM" ;;
    S3) echo "4 vCPU, 7 GB RAM" ;;
    P1V2) echo "1 vCPU, 3.5 GB RAM" ;;
    P2V2) echo "2 vCPU, 7 GB RAM" ;;
    P3V2) echo "4 vCPU, 14 GB RAM" ;;
    P0V3) echo "1 vCPU, 4 GB RAM" ;;
    P1V3) echo "2 vCPU, 8 GB RAM" ;;
    P2V3) echo "4 vCPU, 16 GB RAM" ;;
    P3V3) echo "8 vCPU, 32 GB RAM" ;;
    *) echo "Unknown" ;;
  esac
}

# SKU tier mapping
get_sku_tier() {
  local sku="$1"
  case "${sku^^}" in
    B*) echo "Basic" ;;
    S*) echo "Standard" ;;
    P*V2) echo "PremiumV2" ;;
    P*V3) echo "PremiumV3" ;;
    *) echo "Unknown" ;;
  esac
}

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
    log_error "No resource groups found in subscription"
    log_error "Create one with: az group create --name rg-subnet-calc --location eastus"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    RG_LOCATION=$(az group list --query "[0].location" -o tsv)
    log_info "Found single resource group: ${RESOURCE_GROUP} (${RG_LOCATION})"
    log_info "This appears to be a sandbox or constrained environment."
    read -r -p "Use this resource group? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Check for existing App Service Plans before using default name
if [[ -z "${PLAN_NAME:-}" ]]; then
  log_info "PLAN_NAME not set. Checking for existing App Service Plans..."
  PLAN_COUNT=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${PLAN_COUNT}" -eq 1 ]]; then
    EXISTING_PLAN_NAME=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_PLAN_SKU=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.name" -o tsv)
    EXISTING_PLAN_TIER=$(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[0].sku.tier" -o tsv)

    # Calculate monthly cost for existing plan
    EXISTING_HOURLY=$(get_sku_cost "${EXISTING_PLAN_SKU}")
    EXISTING_MONTHLY=$(awk "BEGIN {printf \"%.2f\", ${EXISTING_HOURLY} * 730}")

    log_info "Found existing App Service Plan: ${EXISTING_PLAN_NAME}"
    log_info "  SKU: ${EXISTING_PLAN_SKU} (${EXISTING_PLAN_TIER})"
    log_info "  Cost: \$${EXISTING_MONTHLY}/month (\$${EXISTING_HOURLY}/hour)"
    log_warn "App Service Plans run 24/7 and cost money even when idle!"
    read -r -p "Use existing App Service Plan? (Y/n): " use_existing
    use_existing=${use_existing:-y}

    if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
      PLAN_NAME="${EXISTING_PLAN_NAME}"

      # Get plan details and exit
      PLAN_ID=$(az appservice plan show \
        --name "${PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id -o tsv)

      PLAN_SPECS=$(get_sku_specs "${EXISTING_PLAN_SKU}")

      log_info ""
      log_info "✓ Using existing App Service Plan"
      log_info ""
      log_info "Plan Details:"
      log_info "  Name: ${PLAN_NAME}"
      log_info "  SKU: ${EXISTING_PLAN_SKU} (${EXISTING_PLAN_TIER})"
      log_info "  Specs: ${PLAN_SPECS}"
      log_info "  Cost: \$${EXISTING_MONTHLY}/month"
      log_info "  Resource ID: ${PLAN_ID}"
      log_info ""
      log_info "Next steps:"
      log_info "  1. Create function on this plan: ./13-create-function-app-on-app-service-plan.sh"
      exit 0
    fi
  elif [[ "${PLAN_COUNT}" -gt 1 ]]; then
    log_error "Multiple App Service Plans already exist in ${RESOURCE_GROUP}:"

    # Calculate total monthly cost
    TOTAL_MONTHLY=0
    while IFS=$'\t' read -r name sku tier; do
      HOURLY=$(get_sku_cost "${sku}")
      MONTHLY=$(awk "BEGIN {printf \"%.2f\", ${HOURLY} * 730}")
      TOTAL_MONTHLY=$(awk "BEGIN {printf \"%.2f\", ${TOTAL_MONTHLY} + ${MONTHLY}}")
      log_error "  - ${name} (${sku}/${tier}) - \$${MONTHLY}/month"
    done < <(az appservice plan list --resource-group "${RESOURCE_GROUP}" --query "[].[name,sku.name,sku.tier]" -o tsv)

    log_error ""
    log_error "Total cost: \$${TOTAL_MONTHLY}/month running 24/7!"
    log_error ""
    log_error "This is expensive and unusual for a single application."
    log_error "Most apps only need ONE App Service Plan."
    log_error ""
    log_error "Use PLAN_NAME environment variable to specify which plan to configure:"
    log_error ""
    log_error "  PLAN_NAME=plan-subnet-calc ./13-create-function-app-on-app-service-plan.sh"
    log_error ""
    log_error "Or clean up unused plans first to save costs:"
    log_error "  az appservice plan delete --name plan-old --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi
fi

# Configuration with defaults
readonly PLAN_NAME="${PLAN_NAME:-plan-subnet-calc}"
readonly PLAN_SKU="${PLAN_SKU:-B1}"
readonly PLAN_OS="${PLAN_OS:-Linux}"

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
    log_info "Detected location from resource group: ${LOCATION}"
  else
    log_error "Resource group ${RESOURCE_GROUP} not found and LOCATION not set"
    log_error "Either create the resource group first or set LOCATION environment variable"
    exit 1
  fi
fi

# Determine --is-linux flag
PLAN_IS_LINUX="true"
if [[ "${PLAN_OS^^}" == "WINDOWS" ]]; then
  PLAN_IS_LINUX="false"
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Plan Name: ${PLAN_NAME}"
log_info "  SKU: ${PLAN_SKU}"
log_info "  OS: ${PLAN_OS}"
log_info "  Tier: $(get_sku_tier "${PLAN_SKU}")"
log_info "  Specs: $(get_sku_specs "${PLAN_SKU}")"

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group ${RESOURCE_GROUP} not found"
  log_error "Create the resource group first or set correct RESOURCE_GROUP variable"
  exit 1
fi

# Check if App Service Plan already exists
if az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then

  # Get existing SKU
  EXISTING_SKU=$(az appservice plan show \
    --name "${PLAN_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "sku.name" \
    -o tsv)

  if [[ "${EXISTING_SKU^^}" == "${PLAN_SKU^^}" ]]; then
    log_info "App Service Plan ${PLAN_NAME} already exists with SKU ${EXISTING_SKU}"
    log_info "Skipping creation (idempotent)"
  else
    log_error "App Service Plan ${PLAN_NAME} already exists with different SKU"
    log_error "  Existing SKU: ${EXISTING_SKU}"
    log_error "  Requested SKU: ${PLAN_SKU}"
    log_error ""
    log_error "Options:"
    log_error "  1. Use existing plan: Remove PLAN_SKU override"
    log_error "  2. Use different name: PLAN_NAME=\"plan-subnet-calc-${PLAN_SKU,,}\" ./12-create-app-service-plan.sh"
    log_error "  3. Delete existing plan: az appservice plan delete --name ${PLAN_NAME} --resource-group ${RESOURCE_GROUP}"
    exit 1
  fi
else
  # Create App Service Plan
  log_info "Creating App Service Plan ${PLAN_NAME}..."

  if [[ "${PLAN_IS_LINUX}" == "true" ]]; then
    az appservice plan create \
      --name "${PLAN_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --location "${LOCATION}" \
      --sku "${PLAN_SKU}" \
      --is-linux \
      --output none
  else
    az appservice plan create \
      --name "${PLAN_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --location "${LOCATION}" \
      --sku "${PLAN_SKU}" \
      --output none
  fi

  log_info "App Service Plan created successfully"
fi

# Get plan details for output
PLAN_ID=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

PLAN_SKU_ACTUAL=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.name" \
  -o tsv)

PLAN_TIER=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "sku.tier" \
  -o tsv)

PLAN_OS_TYPE=$(az appservice plan show \
  --name "${PLAN_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "kind" \
  -o tsv)

# Convert kind to OS name
if [[ "${PLAN_OS_TYPE,,}" == "linux" ]] || [[ "${PLAN_OS_TYPE,,}" == *"linux"* ]]; then
  PLAN_OS_NAME="Linux"
else
  PLAN_OS_NAME="Windows"
fi

# Calculate costs
HOURLY_COST=$(get_sku_cost "${PLAN_SKU_ACTUAL}")
MONTHLY_COST=$(awk "BEGIN {printf \"%.2f\", ${HOURLY_COST} * 730}")
SANDBOX_4H_COST=$(awk "BEGIN {printf \"%.2f\", ${HOURLY_COST} * 4}")

log_info ""
log_info "========================================="
log_info "App Service Plan created successfully!"
log_info "========================================="
log_info ""
log_info "Plan: ${PLAN_NAME}"
log_info "  SKU: ${PLAN_SKU_ACTUAL} (${PLAN_TIER})"
log_info "  Specs: $(get_sku_specs "${PLAN_SKU_ACTUAL}")"
log_info "  OS: ${PLAN_OS_NAME}"
log_info "  Location: ${LOCATION}"
log_info "  Resource ID: ${PLAN_ID}"
log_info ""
log_info "Cost estimate:"
log_info "  Per hour: \$${HOURLY_COST}"
log_info "  Per month (730h): \$${MONTHLY_COST}"
log_info "  4-hour sandbox: \$${SANDBOX_4H_COST}"
log_info ""
log_info "Features:"
if [[ "${PLAN_TIER}" == "Basic" ]]; then
  log_info "  - VNet integration: Yes"
  log_info "  - Always On: Yes"
  log_info "  - Auto-scale: No (manual scale only)"
  log_info "  - Deployment slots: 0"
elif [[ "${PLAN_TIER}" == "Standard" ]]; then
  log_info "  - VNet integration: Yes"
  log_info "  - Always On: Yes"
  log_info "  - Auto-scale: Yes (up to 10 instances)"
  log_info "  - Deployment slots: 5"
elif [[ "${PLAN_TIER}" == "PremiumV2" ]] || [[ "${PLAN_TIER}" == "PremiumV3" ]]; then
  log_info "  - VNet integration: Yes"
  log_info "  - Always On: Yes"
  log_info "  - Auto-scale: Yes (up to 30 instances)"
  log_info "  - Deployment slots: 20"
fi
log_info ""
log_info "Next steps:"
log_info "  1. Migrate function to this plan: ./13-migrate-function-to-app-service-plan.sh"
log_info "  2. Or create new function on this plan:"
log_info "     az functionapp create --name func-new --resource-group ${RESOURCE_GROUP} \\"
log_info "       --plan ${PLAN_NAME} --runtime python --runtime-version 3.11 \\"
log_info "       --storage-account <storage-account-name>"
log_info ""
log_info "To verify the plan:"
log_info "  az appservice plan show --name ${PLAN_NAME} --resource-group ${RESOURCE_GROUP} \\"
log_info "    --query '{name:name,sku:sku.name,tier:sku.tier,os:reserved}' -o table"
log_info ""
