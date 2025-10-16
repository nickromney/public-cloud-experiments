#!/usr/bin/env bash
#
# Configure IP restrictions on Function App to allow only Azure Static Web Apps traffic
#
# This script secures a Function App by:
# 1. Adding an allow rule for the AzureStaticWebApps service tag (all SWAs)
# 2. Adding a deny-all rule with lower priority (blocks all other traffic)
#
# This ensures the Function App can only be accessed through the linked Static Web App,
# preventing direct access and improving security posture.
#
# Usage:
#   # Interactive mode (prompts for values)
#   ./45-configure-ip-restrictions.sh
#
#   # Specify parameters
#   FUNCTION_APP_NAME="func-subnet-calc-123456" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   ./45-configure-ip-restrictions.sh
#
#   # Custom configuration
#   ALLOW_AZURE_PORTAL="true" \
#   FUNCTION_APP_NAME="func-subnet-calc-123456" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   ./45-configure-ip-restrictions.sh
#
# Parameters:
#   FUNCTION_APP_NAME    - Name of the Function App to secure
#   RESOURCE_GROUP       - Resource group containing the Function App
#   ALLOW_AZURE_PORTAL   - Allow Azure Portal access (default: false)
#   ALLOW_CUSTOM_IPS     - Comma-separated list of additional IPs to allow (optional)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Function App must exist
#   - User must have permissions to modify Function App configuration
#
# Security Notes:
#   - Default: Only Azure Static Web Apps can access the Function App
#   - Azure Portal access disabled by default (cannot test functions directly)
#   - Set ALLOW_AZURE_PORTAL=true to enable portal testing
#   - Use ALLOW_CUSTOM_IPS for developer IP allowlist
#   - Priority numbers: 100 (allow rules), 65000 (deny-all)
#
# Warning:
#   This script will REPLACE existing IP restrictions!
#   To preserve existing rules, modify the script or manage rules manually.

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

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Configuration
readonly ALLOW_AZURE_PORTAL="${ALLOW_AZURE_PORTAL:-false}"
readonly ALLOW_CUSTOM_IPS="${ALLOW_CUSTOM_IPS:-}"

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
  log_info "FUNCTION_APP_NAME not set. Looking for Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 0 ]]; then
    log_error "No Function Apps found in resource group ${RESOURCE_GROUP}"
    exit 1
  elif [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Function App: ${FUNCTION_APP_NAME}"
  else
    log_warn "Multiple Function Apps found:"
    FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${FUNCTION_APP_NAME}"
  fi
fi

log_info ""
log_info "========================================="
log_info "IP Restriction Configuration"
log_info "========================================="
log_info "Resource Group:     ${RESOURCE_GROUP}"
log_info "Function App:       ${FUNCTION_APP_NAME}"
log_info "Allow Azure Portal: ${ALLOW_AZURE_PORTAL}"
log_info "Custom IPs:         ${ALLOW_CUSTOM_IPS:-none}"
log_info ""

# Verify Function App exists
log_step "Verifying Function App exists..."
if ! az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Function App ${FUNCTION_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Function App found"

# Check existing IP restrictions
log_step "Checking existing IP restrictions..."
EXISTING_RULES=$(az functionapp config access-restriction show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipSecurityRestrictions[?name!='Allow all'].name" -o tsv 2>/dev/null || echo "")

if [[ -n "${EXISTING_RULES}" ]]; then
  log_warn "Function App has existing IP restrictions:"
  echo "${EXISTING_RULES}" | while read -r rule; do
    echo "  - ${rule}"
  done
  log_warn ""
  log_warn "This script will REPLACE all existing rules!"
  echo ""
  read -r -p "Continue? (y/N): " confirm
  confirm=${confirm:-n}
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled"
    exit 0
  fi
fi

# Remove all existing IP restrictions (start fresh)
log_step "Removing existing IP restrictions..."
az functionapp config access-restriction remove \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "Allow all" \
  --output none 2>/dev/null || true

# Remove any custom rules
if [[ -n "${EXISTING_RULES}" ]]; then
  echo "${EXISTING_RULES}" | while read -r rule; do
    az functionapp config access-restriction remove \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --rule-name "${rule}" \
      --output none 2>/dev/null || true
  done
fi

log_info "Existing restrictions removed"

# Add allow rule for Azure Static Web Apps service tag
log_step "Adding allow rule for AzureStaticWebApps service tag..."
az functionapp config access-restriction add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "Allow Azure Static Web Apps" \
  --action Allow \
  --priority 100 \
  --service-tag AzureStaticWebApps \
  --output none

log_info "AzureStaticWebApps service tag allow rule added (priority 100)"

# Add allow rule for Azure Portal if requested
NEXT_PRIORITY=110
if [[ "${ALLOW_AZURE_PORTAL}" == "true" ]]; then
  log_step "Adding allow rule for Azure Portal..."
  az functionapp config access-restriction add \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --rule-name "Allow Azure Portal" \
    --action Allow \
    --priority ${NEXT_PRIORITY} \
    --service-tag AzureCloud \
    --output none

  log_info "Azure Portal access enabled (priority ${NEXT_PRIORITY})"
  ((NEXT_PRIORITY += 10))
fi

# Add custom IP addresses if provided
if [[ -n "${ALLOW_CUSTOM_IPS}" ]]; then
  log_step "Adding custom IP allow rules..."
  IFS=',' read -ra IPS <<< "${ALLOW_CUSTOM_IPS}"
  for ip in "${IPS[@]}"; do
    # Trim whitespace
    ip=$(echo "${ip}" | xargs)

    # Validate IP format (basic check)
    if [[ ! "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
      log_warn "Skipping invalid IP format: ${ip}"
      continue
    fi

    # Ensure CIDR notation
    if [[ ! "${ip}" =~ / ]]; then
      ip="${ip}/32"
    fi

    log_info "Adding allow rule for ${ip}..."
    az functionapp config access-restriction add \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --rule-name "Allow Custom IP ${ip}" \
      --action Allow \
      --priority ${NEXT_PRIORITY} \
      --ip-address "${ip}" \
      --output none

    log_info "Custom IP ${ip} allowed (priority ${NEXT_PRIORITY})"
    ((NEXT_PRIORITY += 10))
  done
fi

# Add deny-all rule with lowest priority
log_step "Adding deny-all rule..."
# Note: Azure uses priority 2147483647 for implicit deny-all
# We set an explicit deny at priority 65000 to make it visible
az functionapp config access-restriction add \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --rule-name "Deny All" \
  --action Deny \
  --priority 65000 \
  --ip-address "0.0.0.0/0" \
  --output none

log_info "Deny-all rule added (priority 65000)"

# Verify configuration
log_step "Verifying IP restriction configuration..."
FINAL_RULES=$(az functionapp config access-restriction show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipSecurityRestrictions[].[name,action,priority,ipAddress,tag]" -o tsv)

log_info "Current IP restrictions:"
echo "${FINAL_RULES}" | while IFS=$'\t' read -r name action priority ip_or_tag service_tag; do
  if [[ -n "${service_tag}" && "${service_tag}" != "None" ]]; then
    echo "  - ${name}: ${action} (priority ${priority}, tag: ${service_tag})"
  else
    echo "  - ${name}: ${action} (priority ${priority}, IP: ${ip_or_tag})"
  fi
done

# Get Function App URL
FUNC_HOSTNAME=$(az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")

# Handle empty hostname (Flex Consumption)
if [[ -z "${FUNC_HOSTNAME}" ]]; then
  FUNC_HOSTNAME="${FUNCTION_APP_NAME}.azurewebsites.net"
fi

log_info ""
log_info "========================================="
log_info "IP Restrictions Configured Successfully!"
log_info "========================================="
log_info "Function App: ${FUNCTION_APP_NAME}"
log_info "  URL: https://${FUNC_HOSTNAME}"
log_info ""
log_info "Access Policy:"
log_info "  - Azure Static Web Apps: ALLOWED"
if [[ "${ALLOW_AZURE_PORTAL}" == "true" ]]; then
  log_info "  - Azure Portal: ALLOWED"
else
  log_info "  - Azure Portal: DENIED"
fi
if [[ -n "${ALLOW_CUSTOM_IPS}" ]]; then
  log_info "  - Custom IPs: ALLOWED (${ALLOW_CUSTOM_IPS})"
fi
log_info "  - All other traffic: DENIED"
log_info ""
log_info "Security Status:"
log_info "  - Function App is now protected"
log_info "  - Direct access from internet is blocked"
log_info "  - Only Static Web Apps can call the API"
log_info ""
log_info "Testing:"
log_info "  # This should fail (direct access blocked):"
log_info "  curl https://${FUNC_HOSTNAME}/api/v1/health"
log_info ""
log_info "  # Access via Static Web App (if linked):"
log_info "  # Find your SWA hostname and use that instead"
log_info ""
log_info "To remove IP restrictions:"
log_info "  az functionapp config access-restriction remove \\"
log_info "    --name ${FUNCTION_APP_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP} \\"
log_info "    --rule-name \"Allow Azure Static Web Apps\""
log_info ""
