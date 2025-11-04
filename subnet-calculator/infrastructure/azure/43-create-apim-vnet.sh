#!/usr/bin/env bash
#
# 43-create-apim-vnet.sh - Create Azure API Management with VNet Integration
#
# This script creates an APIM instance integrated into a virtual network.
# Supports both External and Internal VNet modes:
#
# External Mode (Stack 17):
#   - APIM gateway endpoint is publicly accessible (internet)
#   - APIM can reach private backends within VNet
#   - Enables SWA→APIM linking (az staticwebapp backends link)
#   - Use case: Public API gateway with private backends
#
# Internal Mode (Stack 18):
#   - APIM gateway endpoint is private (VNet only)
#   - Requires Application Gateway or VPN for public access
#   - Cannot use SWA→APIM linking (network isolated backend limitation)
#   - Use case: Fully private architecture, maximum security
#
# Usage:
#   # External mode (default for Stack 17)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-platform" \
#   APIM_VNET_MODE="External" \
#   ./43-create-apim-vnet.sh
#
#   # Internal mode (for Stack 18)
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-platform" \
#   APIM_VNET_MODE="Internal" \
#   ./43-create-apim-vnet.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP     - Resource group name
#   VNET_NAME          - Virtual network name
#   APIM_VNET_MODE     - "External" or "Internal"
#
# Optional Environment Variables:
#   APIM_NAME          - APIM instance name (default: apim-subnet-calc-[random])
#   APIM_SKU           - SKU tier (default: Developer)
#   APIM_SUBNET_NAME   - Subnet for APIM (default: snet-apim)
#   APIM_SUBNET_PREFIX - Subnet CIDR (default: 10.100.0.64/27)
#   PUBLISHER_EMAIL    - Publisher email (auto-detected from Azure account)
#   PUBLISHER_NAME     - Publisher name (default: Subnet Calculator)
#   LOCATION           - Azure region (auto-detected from resource group)
#
# Exit Codes:
#   0 - Success (APIM instance created successfully)
#   1 - Error (validation failed, creation failed, timeout)
#
# Provisioning Time:
#   - Developer SKU: ~37-45 minutes
#   - VNet integration adds ~5-10 minutes
#   - Total: Plan for ~45-55 minutes
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-vnet

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

# Get script directory and source selection utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  log_error "Example: RESOURCE_GROUP='rg-subnet-calc' $0"
  exit 1
fi

if [[ -z "${VNET_NAME:-}" ]]; then
  log_error "VNET_NAME environment variable is required"
  log_error "Example: VNET_NAME='vnet-platform' $0"
  exit 1
fi

if [[ -z "${APIM_VNET_MODE:-}" ]]; then
  log_error "APIM_VNET_MODE environment variable is required"
  log_error "Must be either 'External' or 'Internal'"
  log_error ""
  log_error "External: Public gateway, private backends (for Stack 17)"
  log_error "Internal: Private gateway (for Stack 18)"
  log_error ""
  log_error "Example: APIM_VNET_MODE='External' $0"
  exit 1
fi

# Validate APIM_VNET_MODE
if [[ "${APIM_VNET_MODE}" != "External" && "${APIM_VNET_MODE}" != "Internal" ]]; then
  log_error "Invalid APIM_VNET_MODE: ${APIM_VNET_MODE}"
  log_error "Must be either 'External' or 'Internal'"
  exit 1
fi

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group '${RESOURCE_GROUP}' not found"
  exit 1
fi

# Get location from resource group
LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
log_info "Location: ${LOCATION}"

# Verify VNet exists
# shellcheck disable=SC2034
if ! VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "VNet '${VNET_NAME}' not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "VNet found: ${VNET_NAME}"

# Configuration with defaults
readonly APIM_SUBNET_NAME="${APIM_SUBNET_NAME:-snet-apim}"
readonly APIM_SUBNET_PREFIX="${APIM_SUBNET_PREFIX:-10.100.0.64/27}"
readonly APIM_SKU="${APIM_SKU:-Developer}"
readonly PUBLISHER_NAME="${PUBLISHER_NAME:-Subnet Calculator}"

# Auto-detect or prompt for PUBLISHER_EMAIL
if [[ -z "${PUBLISHER_EMAIL:-}" ]]; then
  log_info "PUBLISHER_EMAIL not set. Detecting from Azure account..."
  PUBLISHER_EMAIL=$(az account show --query user.name -o tsv 2>/dev/null || echo "")

  if [[ -z "${PUBLISHER_EMAIL}" ]]; then
    log_warn "Could not auto-detect email from Azure account"
    read -r -p "Enter publisher email address: " PUBLISHER_EMAIL

    if [[ -z "${PUBLISHER_EMAIL}" ]]; then
      log_error "Publisher email is required for APIM"
      exit 1
    fi
  else
    log_info "Auto-detected email: ${PUBLISHER_EMAIL}"
  fi
fi

# Check if APIM instance already exists in resource group
if [[ -z "${APIM_NAME:-}" ]]; then
  log_info "APIM_NAME not set. Checking for existing APIM instances..."
  EXISTING_APIM_COUNT=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${EXISTING_APIM_COUNT}" -eq 1 ]]; then
    EXISTING_APIM_NAME=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    EXISTING_APIM_STATE=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].provisioningState" -o tsv)
    EXISTING_APIM_VNET_TYPE=$(az apim list --resource-group "${RESOURCE_GROUP}" --query "[0].virtualNetworkType" -o tsv)

    log_info "Found existing APIM instance: ${EXISTING_APIM_NAME}"
    log_info "  State: ${EXISTING_APIM_STATE}"
    log_info "  VNet Type: ${EXISTING_APIM_VNET_TYPE:-None}"

    if [[ "${EXISTING_APIM_STATE}" == "Succeeded" ]]; then
      log_warn "APIM instance already exists!"
      read -r -p "Use existing APIM instance? (Y/n): " use_existing
      use_existing=${use_existing:-y}

      if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
        APIM_NAME="${EXISTING_APIM_NAME}"

        # Verify VNet mode matches
        if [[ "${EXISTING_APIM_VNET_TYPE}" != "${APIM_VNET_MODE}" ]]; then
          log_error "Existing APIM has VNet type: ${EXISTING_APIM_VNET_TYPE}"
          log_error "Requested VNet type: ${APIM_VNET_MODE}"
          log_error "Cannot change VNet mode on existing APIM"
          exit 1
        fi

        # Get details and exit
        APIM_GATEWAY=$(az apim show \
          --name "${APIM_NAME}" \
          --resource-group "${RESOURCE_GROUP}" \
          --query gatewayUrl -o tsv)

        log_info ""
        log_info "✓ Using existing APIM instance"
        log_info ""
        log_info "APIM Instance Details:"
        log_info "  Name: ${APIM_NAME}"
        log_info "  VNet Mode: ${EXISTING_APIM_VNET_TYPE}"
        log_info "  Gateway URL: ${APIM_GATEWAY}"
        log_info ""
        exit 0
      fi
    fi
  elif [[ "${EXISTING_APIM_COUNT}" -gt 1 ]]; then
    log_error "Multiple APIM instances already exist in ${RESOURCE_GROUP}"
    log_error "Use APIM_NAME environment variable to select which one to configure"
    az apim list --resource-group "${RESOURCE_GROUP}" --query "[].[name,virtualNetworkType,provisioningState]" -o table
    exit 1
  fi
fi

# Generate random name if still not set
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
readonly APIM_NAME="${APIM_NAME:-apim-subnet-calc-${RANDOM_SUFFIX}}"

log_info ""
log_info "========================================="
log_info "APIM VNet Integration Configuration"
log_info "========================================="
log_info "Resource Group:   ${RESOURCE_GROUP}"
log_info "Location:         ${LOCATION}"
log_info "APIM Name:        ${APIM_NAME}"
log_info "SKU:              ${APIM_SKU}"
log_info "VNet:             ${VNET_NAME}"
log_info "VNet Mode:        ${APIM_VNET_MODE}"
log_info "APIM Subnet:      ${APIM_SUBNET_NAME} (${APIM_SUBNET_PREFIX})"
log_info "Publisher Email:  ${PUBLISHER_EMAIL}"
log_info "Publisher Name:   ${PUBLISHER_NAME}"
log_info ""

# Check if APIM subnet exists, create if not
log_step "Checking for APIM subnet..."
if az network vnet subnet show \
  --name "${APIM_SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "APIM subnet ${APIM_SUBNET_NAME} already exists"
else
  log_info "Creating APIM subnet ${APIM_SUBNET_NAME}..."
  az network vnet subnet create \
    --name "${APIM_SUBNET_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --address-prefix "${APIM_SUBNET_PREFIX}" \
    --output none

  log_info "APIM subnet created"
fi

# Get subnet resource ID for VNet integration
SUBNET_ID=$(az network vnet subnet show \
  --name "${APIM_SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info "Subnet ID: ${SUBNET_ID}"

# Check if APIM instance already exists
if az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then

  # Get existing APIM VNet type
  EXISTING_VNET_TYPE=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "virtualNetworkType" -o tsv 2>/dev/null || echo "None")

  # Check if VNet mode matches
  if [[ "${EXISTING_VNET_TYPE}" == "${APIM_VNET_MODE}" ]]; then
    log_info "APIM instance ${APIM_NAME} already exists with VNet mode: ${EXISTING_VNET_TYPE}"
    log_info "Skipping APIM creation, will use existing instance"
    log_info ""

    # Get gateway URL
    APIM_GATEWAY=$(az apim show \
      --name "${APIM_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "gatewayUrl" -o tsv)

    log_info "✓ APIM Instance Created Successfully!"
    log_info ""
    log_info "========================================="
    log_info "APIM Details"
    log_info "========================================="
    log_info "Name:             ${APIM_NAME}"
    log_info "VNet Mode:        ${EXISTING_VNET_TYPE}"
    log_info "Gateway URL:      ${APIM_GATEWAY}"
    log_info "Developer Portal: https://${APIM_NAME}.developer.azure-api.net"
    log_info "Private IP:       N/A"
    log_info ""

    if [[ "${APIM_VNET_MODE}" == "Internal" ]]; then
      log_info "Internal Mode:"
      log_info "  ✓ Gateway is private (VNet only)"
      log_info "  ✓ Gets private IP via VNet injection"
      log_info "  ✓ Requires Application Gateway for public access"
      log_info "  ⚠️  NOT compatible with SWA→APIM linking"
    else
      log_info "External Mode:"
      log_info "  ✓ Gateway is public"
      log_info "  ✓ Can reach private backends via VNet"
      log_info "  ✓ Compatible with SWA→APIM linking"
    fi

    log_info ""
    if [[ "${APIM_VNET_MODE}" == "Internal" ]]; then
      log_info "Next Steps (Stack 18 - Internal):"
      log_info "  1. Configure backend: ./31-apim-backend.sh"
      log_info "  2. Apply policies: ./32-apim-policies.sh"
      log_info "  3. Configure AppGW path-based routing: ./55-add-path-based-routing.sh"
      log_info "  Note: Private endpoint NOT needed (VNet injection provides private IP)"
    else
      log_info "Next Steps (Stack 17 - External):"
      log_info "  1. Configure backend: ./31-apim-backend.sh"
      log_info "  2. Apply policies: ./32-apim-policies.sh"
      log_info "  3. Link to SWA (optional): Use APIM as backend for SWA"
    fi
    log_info ""
    log_info "Save this APIM name for other scripts: ${APIM_NAME}"
    log_info ""

    # Exit successfully - instance already exists with correct configuration
    exit 0
  else
    log_error "APIM instance ${APIM_NAME} already exists with VNet mode: ${EXISTING_VNET_TYPE}"
    log_error "Requested VNet mode: ${APIM_VNET_MODE}"
    log_error "Cannot change VNet mode on existing APIM instance"
    exit 1
  fi
fi

# Create APIM instance with VNet integration
log_warn "Creating APIM instance with VNet integration..."
log_warn "⏱️  VNet Mode: ${APIM_VNET_MODE}"
log_warn "⏱️  This will take approximately 45-55 minutes"
log_warn "⏱️  External mode: Gateway is public, can reach private backends"
log_warn "⏱️  Internal mode: Gateway is private (VNet only)"
log_info ""

START_TIME=$(date +%s)

# Create APIM instance with VNet type specified
# Note: VNet type (External/Internal) is set at creation
#       Subnet configuration will be applied via REST API after provisioning
log_info "Creating APIM instance with VNet type: ${APIM_VNET_MODE}..."
az apim create \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --publisher-email "${PUBLISHER_EMAIL}" \
  --publisher-name "${PUBLISHER_NAME}" \
  --sku-name "${APIM_SKU}" \
  --virtual-network "${APIM_VNET_MODE}" \
  --no-wait \
  --output none

log_info "APIM creation initiated (running in background)"
log_info "Waiting for APIM to be provisioned before applying VNet configuration..."

# Wait for APIM to be created
APIM_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}"

# Poll until APIM is created (or timeout after 60 minutes)
TIMEOUT=3600
ELAPSED=0
INTERVAL=30

while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
  APIM_STATE=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")

  if [[ "${APIM_STATE}" == "Succeeded" ]]; then
    log_info "✓ APIM instance provisioned successfully"
    break
  elif [[ "${APIM_STATE}" == "Failed" ]]; then
    log_error "APIM provisioning failed"
    exit 1
  fi

  if [[ $((ELAPSED % 300)) -eq 0 ]]; then
    log_info "APIM provisioning status: ${APIM_STATE} (${ELAPSED}s elapsed)"
  fi

  sleep ${INTERVAL}
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
  log_error "Timeout waiting for APIM to be provisioned"
  exit 1
fi

# Apply VNet configuration using REST API
# Note: Must set BOTH virtualNetworkType AND virtualNetworkConfiguration together
log_info "Applying VNet configuration (${APIM_VNET_MODE} mode)..."

az rest \
  --method PATCH \
  --uri "${APIM_ID}?api-version=2023-05-01-preview" \
  --body "{
    \"properties\": {
      \"virtualNetworkType\": \"${APIM_VNET_MODE}\",
      \"virtualNetworkConfiguration\": {
        \"subnetResourceId\": \"${SUBNET_ID}\"
      }
    }
  }"

log_info "VNet configuration applied. APIM will update in background (~10-15 min)"
log_info "Waiting for provisioning to complete..."

# Poll for completion
ELAPSED=0
while true; do
  PROVISIONING_STATE=$(az apim show \
    --name "${APIM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

  ELAPSED=$(($(date +%s) - START_TIME))
  MINUTES=$((ELAPSED / 60))

  case "${PROVISIONING_STATE}" in
    Succeeded)
      log_info "✓ APIM instance created successfully (took ${MINUTES} minutes)"
      break
      ;;
    Failed)
      log_error "APIM creation failed"
      log_error "Check Azure Portal for error details"
      exit 1
      ;;
    NotFound)
      log_info "Waiting for APIM creation to start... (${MINUTES}m elapsed)"
      ;;
    *)
      log_info "Provisioning state: ${PROVISIONING_STATE} (${MINUTES}m elapsed)"
      ;;
  esac

  sleep 30
done

# Get APIM details
APIM_INFO=$(az apim show \
  --name "${APIM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{gatewayUrl:gatewayUrl,portalUrl:developerPortalUrl,vnetType:virtualNetworkType,privateIp:privateIPAddresses[0]}" -o json)

APIM_GATEWAY=$(echo "${APIM_INFO}" | jq -r '.gatewayUrl')
APIM_PORTAL=$(echo "${APIM_INFO}" | jq -r '.portalUrl // "Not available"')
APIM_VNET_TYPE=$(echo "${APIM_INFO}" | jq -r '.vnetType')
APIM_PRIVATE_IP=$(echo "${APIM_INFO}" | jq -r '.privateIp // "N/A"')

log_info ""
log_info "✓ APIM Instance Created Successfully!"
log_info ""
log_info "========================================="
log_info "APIM Details"
log_info "========================================="
log_info "Name:             ${APIM_NAME}"
log_info "VNet Mode:        ${APIM_VNET_TYPE}"
log_info "Gateway URL:      ${APIM_GATEWAY}"
log_info "Developer Portal: ${APIM_PORTAL}"
log_info "Private IP:       ${APIM_PRIVATE_IP}"
log_info ""

if [[ "${APIM_VNET_TYPE}" == "External" ]]; then
  log_info "External Mode:"
  log_info "  ✓ Gateway is publicly accessible"
  log_info "  ✓ Can reach private backends in VNet"
  log_info "  ✓ Compatible with SWA→APIM linking (Stack 17)"
  log_info ""
  log_info "Next Steps (Stack 17):"
  log_info "  1. Configure backend: ./31-apim-backend.sh"
  log_info "  2. Apply policies: ./32-apim-policies.sh"
  log_info "  3. Link SWA to APIM: ./44-link-swa-to-apim.sh"
elif [[ "${APIM_VNET_TYPE}" == "Internal" ]]; then
  log_info "Internal Mode:"
  log_info "  ✓ Gateway is private (VNet only)"
  log_info "  ✓ Gets private IP via VNet injection"
  log_info "  ✓ Requires Application Gateway for public access"
  log_info "  ⚠️  NOT compatible with SWA→APIM linking"
  log_info ""
  log_info "Next Steps (Stack 18):"
  log_info "  1. Configure backend: ./31-apim-backend.sh"
  log_info "  2. Apply policies: ./32-apim-policies.sh"
  log_info "  3. Configure AppGW path-based routing: ./55-add-path-based-routing.sh"
  log_info "  Note: Private endpoint NOT needed (VNet injection provides private IP)"
fi

log_info ""
log_info "Save this APIM name for other scripts: ${APIM_NAME}"
log_info ""
