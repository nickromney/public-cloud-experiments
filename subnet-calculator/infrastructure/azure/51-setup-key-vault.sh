#!/usr/bin/env bash
#
# 51-setup-key-vault.sh - Setup or Detect Azure Key Vault
#
# This script ensures a Key Vault exists in the resource group.
# It can detect existing Key Vaults or create a new one with a unique name.
#
# Usage:
# # Auto-detect single Key Vault or create new
# RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" ./51-setup-key-vault.sh
#
# # Use specific Key Vault (if multiple exist)
# RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" \
# KEY_VAULT_NAME="kv-subnet-calc-abcd" ./51-setup-key-vault.sh
#
# Input (environment variables required):
# RESOURCE_GROUP - Azure resource group name
# LOCATION - Azure region (e.g., uksouth)
#
# Input (environment variables optional):
# KEY_VAULT_NAME - Specific Key Vault name (required if multiple exist)
#
# Output (exported environment variables):
# KEY_VAULT_NAME - Name of the Key Vault
# KEY_VAULT_ID - Full resource ID of the Key Vault
#
# Behavior:
# - 0 Key Vaults: Create new with random suffix
# - 1 Key Vault: Auto-detect and use
# - Multiple Key Vaults: Error unless KEY_VAULT_NAME specified
#
# Exit Codes:
# 0 - Success (Key Vault ready)
# 1 - Error (missing env vars, multiple KVs without name, creation failed)

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

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  log_error "Usage: RESOURCE_GROUP=rg-name LOCATION=region $0"
  exit 1
fi

if [[ -z "${LOCATION:-}" ]]; then
  log_error "LOCATION environment variable is required"
  log_error "Usage: RESOURCE_GROUP=rg-name LOCATION=region $0"
  exit 1
fi

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_step "Setting up Key Vault in ${RESOURCE_GROUP}..."

# Count Key Vaults in resource group
KV_COUNT=$(az keyvault list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [[ "${KV_COUNT}" -eq 1 ]]; then
  # Single Key Vault: Auto-detect
  KEY_VAULT_NAME=$(az keyvault list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].name" -o tsv)
  log_info "Found existing Key Vault: ${KEY_VAULT_NAME}"

elif [[ "${KV_COUNT}" -gt 1 ]]; then
  # Multiple Key Vaults: Require KEY_VAULT_NAME
  if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
    log_error "Multiple Key Vaults found in ${RESOURCE_GROUP}"
    log_error "Specify which one to use: KEY_VAULT_NAME='kv-name' $0"
    log_error ""
    log_error "Available Key Vaults:"
    az keyvault list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[].[name, properties.provisioningState]" -o table
    exit 1
  fi
  log_info "Using specified Key Vault: ${KEY_VAULT_NAME}"

else
  # No Key Vaults: Create new with unique name
  KV_SUFFIX=$(openssl rand -hex 2) # 4 hex chars for uniqueness
  KEY_VAULT_NAME="kv-subnet-calc-${KV_SUFFIX}"

  log_info "No Key Vault found. Creating: ${KEY_VAULT_NAME}..."
  if az keyvault create \
    --name "${KEY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --enable-rbac-authorization true \
    --sku standard \
    --output none; then
    log_info "Key Vault created successfully"
  else
    log_error "Failed to create Key Vault"
    exit 1
  fi
fi

# Verify Key Vault is accessible
if ! az keyvault show --name "${KEY_VAULT_NAME}" &>/dev/null; then
  log_error "Key Vault '${KEY_VAULT_NAME}' not accessible"
  log_error "Check that it exists and you have permissions"
  exit 1
fi

# Get Key Vault resource ID for RBAC assignments
KEY_VAULT_ID=$(az keyvault show \
  --name "${KEY_VAULT_NAME}" \
  --query "id" -o tsv)

log_info "Key Vault ready: ${KEY_VAULT_NAME}"
log_info "Resource ID: ${KEY_VAULT_ID}"

# Export for caller scripts
export KEY_VAULT_NAME
export KEY_VAULT_ID

log_info "Exported KEY_VAULT_NAME and KEY_VAULT_ID"
