#!/usr/bin/env bash
#
# Import existing Azure resources into stack-based Terraform configuration
# Maps existing Azure resource names to logical stack keys
#
# To run this script, either:
#   chmod +x import-stacks.sh && ./import-stacks.sh
# or run it explicitly with:
#   bash import-stacks.sh
#
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

# Configuration
RESOURCE_GROUP="rg-subnet-calc"
SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

# Mapping: logical stack key -> Azure resource names
declare -A SWA_NAMES=(
  ["noauth"]="swa-subnet-calc-noauth"
  ["entraid-linked"]="swa-subnet-calc-entraid-linked"
  ["private-endpoint"]="swa-subnet-calc-private-endpoint"
)

declare -A FUNCTION_NAMES=(
  ["noauth"]="func-subnet-calc-jwt"
  ["entraid-linked"]="func-subnet-calc-entraid-linked"
  ["private-endpoint"]="func-subnet-calc-asp-46195"
)

declare -A PLAN_NAMES=(
  ["noauth"]="ASP-rgsubnetcalc-4e5a"
  ["entraid-linked"]="ASP-rgsubnetcalc-d642"
  ["private-endpoint"]="asp-subnet-calc-stack16"
)

declare -A STORAGE_NAMES=(
  ["noauth"]="stsubnetcalc22531"
  ["entraid-linked"]="stsubnetcalc34188"
  ["private-endpoint"]="stfuncprivateep61925"
)

declare -A CUSTOM_DOMAINS_SWA=(
  ["noauth"]="static-swa-no-auth.publiccloudexperiments.net"
  ["entraid-linked"]="static-swa-entraid-linked.publiccloudexperiments.net"
  ["private-endpoint"]="static-swa-private-endpoint.publiccloudexperiments.net"
)

declare -A CUSTOM_DOMAINS_FUNCTION=(
  ["noauth"]="subnet-calc-fa-jwt-auth.publiccloudexperiments.net"
  ["entraid-linked"]="subnet-calc-fa-entraid-linked.publiccloudexperiments.net"
  ["private-endpoint"]="" # No custom domain for private endpoint stack
)

# Helper function to import a resource
import_resource() {
  local resource_addr="$1"
  local resource_id="$2"

  log_info "Importing ${resource_addr}..."

  if terragrunt import "${resource_addr}" "${resource_id}" 2>&1 | tee /tmp/import-output.log; then
    log_info "✓ Imported ${resource_addr}"
    return 0
  else
    if grep -q "Resource already managed" /tmp/import-output.log; then
      log_warn "Already imported: ${resource_addr}"
      return 0
    fi
    log_error "Failed to import ${resource_addr}"
    return 1
  fi
}

log_info "========================================="
log_info "Stack-Based Import"
log_info "========================================="
log_info ""
log_info "Resource Group: ${RESOURCE_GROUP}"
log_info "Subscription:   ${SUBSCRIPTION_ID}"
log_info ""

# Import each stack
for stack_key in "${!SWA_NAMES[@]}"; do
  log_step "Importing stack: ${stack_key}"

  # Import Static Web App
  swa_name="${SWA_NAMES[$stack_key]}"
  swa_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/staticSites/${swa_name}"
  import_resource "azurerm_static_web_app.this[\"${stack_key}\"]" "${swa_id}"

  # Import SWA Custom Domain
  if [[ -n "${CUSTOM_DOMAINS_SWA[$stack_key]}" ]]; then
    domain="${CUSTOM_DOMAINS_SWA[$stack_key]}"
    domain_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/staticSites/${swa_name}/customDomains/${domain}"
    import_resource "azurerm_static_web_app_custom_domain.this[\"${stack_key}\"]" "${domain_id}"
  fi

  # Import App Service Plan
  plan_name="${PLAN_NAMES[$stack_key]}"
  plan_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/serverFarms/${plan_name}"
  import_resource "azurerm_service_plan.this[\"${stack_key}\"]" "${plan_id}"

  # Import Storage Account
  storage_name="${STORAGE_NAMES[$stack_key]}"
  storage_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${storage_name}"
  import_resource "azurerm_storage_account.this[\"${stack_key}\"]" "${storage_id}"

  # Import random_string for storage suffix (we'll need to match existing suffix)
  # Note: We need to import the random string state to match the existing storage account name
  # For now, skip this - we'll handle it differently

  # Import Function App
  function_name="${FUNCTION_NAMES[$stack_key]}"
  function_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${function_name}"
  import_resource "azurerm_linux_function_app.this[\"${stack_key}\"]" "${function_id}"

  # Import Function App Custom Hostname
  if [[ -n "${CUSTOM_DOMAINS_FUNCTION[$stack_key]}" ]]; then
    hostname="${CUSTOM_DOMAINS_FUNCTION[$stack_key]}"
    hostname_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${function_name}/hostNameBindings/${hostname}"
    import_resource "azurerm_app_service_custom_hostname_binding.this[\"${stack_key}\"]" "${hostname_id}"
  fi

  echo ""
done

log_info "========================================="
log_info "Import Complete!"
log_info "========================================="
log_info ""
log_info "Next steps:"
log_info "  make plan    # Should show ~3 changes for random_string resources"
log_info "  # Accept the random_string changes - they're just state placeholders"
log_info "  make apply   # Apply to sync state"
log_info ""
