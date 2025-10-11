#!/usr/bin/env bash
#
# Clean up all Azure resources created for subnet calculator
# - Deletes Static Web App
# - Deletes Function App
# - Deletes Storage Account
# - Optionally deletes Resource Group
#
# Usage:
#   ./99-cleanup.sh                    # Delete resources but keep RG
#   DELETE_RG=true ./99-cleanup.sh     # Delete everything including RG

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-subnet-calc}"
readonly STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-subnet-calc}"
readonly FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-subnet-calc}"
readonly DELETE_RG="${DELETE_RG:-false}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Check if resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_warn "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
  exit 0
fi

log_warn "========================================="
log_warn "WARNING: This will delete Azure resources!"
log_warn "========================================="
log_warn "Resource Group: ${RESOURCE_GROUP}"
log_warn ""

if [[ "${DELETE_RG}" == "true" ]]; then
  log_warn "This will DELETE THE ENTIRE RESOURCE GROUP and ALL resources in it!"
  log_warn ""
  read -p "Are you sure? Type 'yes' to confirm: " -r
  if [[ ! $REPLY == "yes" ]]; then
    log_info "Cleanup cancelled"
    exit 0
  fi

  log_info "Deleting resource group ${RESOURCE_GROUP}..."
  az group delete \
    --name "${RESOURCE_GROUP}" \
    --yes \
    --no-wait

  log_info ""
  log_info "Resource group deletion initiated (running in background)"
  log_info "All resources in the group will be deleted"
  log_info ""
  log_info "To check status:"
  log_info "  az group show --name ${RESOURCE_GROUP}"
  exit 0
fi

# Delete individual resources (keep RG for sandbox environments)
log_warn "This will delete individual resources but keep the resource group"
log_warn "(Use DELETE_RG=true to delete the entire resource group)"
log_warn ""
read -p "Continue? Type 'yes' to confirm: " -r
if [[ ! $REPLY == "yes" ]]; then
  log_info "Cleanup cancelled"
  exit 0
fi

# Delete Static Web App
if az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Deleting Static Web App ${STATIC_WEB_APP_NAME}..."
  az staticwebapp delete \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --yes \
    --output none
  log_info "Static Web App deleted"
else
  log_info "Static Web App ${STATIC_WEB_APP_NAME} not found (skipping)"
fi

# Delete Function App
if az functionapp show \
  --name "${FUNCTION_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Deleting Function App ${FUNCTION_APP_NAME}..."
  az functionapp delete \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output none
  log_info "Function App deleted"
else
  log_info "Function App ${FUNCTION_APP_NAME} not found (skipping)"
fi

# Find and delete storage accounts
log_info "Finding storage accounts in resource group..."
STORAGE_ACCOUNTS=$(az storage account list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].name" -o tsv)

if [[ -n "${STORAGE_ACCOUNTS}" ]]; then
  while IFS= read -r storage_account; do
    log_info "Deleting storage account ${storage_account}..."
    az storage account delete \
      --name "${storage_account}" \
      --resource-group "${RESOURCE_GROUP}" \
      --yes \
      --output none
    log_info "Storage account ${storage_account} deleted"
  done <<< "${STORAGE_ACCOUNTS}"
else
  log_info "No storage accounts found (skipping)"
fi

log_info ""
log_info "========================================="
log_info "Cleanup completed!"
log_info "========================================="
log_info "Deleted resources from: ${RESOURCE_GROUP}"
log_info "Resource group preserved: ${RESOURCE_GROUP}"
log_info ""
log_info "To delete the resource group later, run:"
log_info "  DELETE_RG=true ./99-cleanup.sh"
log_info ""
log_info "Or manually:"
log_info "  az group delete --name ${RESOURCE_GROUP} --yes"
