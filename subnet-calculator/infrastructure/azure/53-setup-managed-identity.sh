#!/usr/bin/env bash
#
# 53-setup-managed-identity.sh - Setup User-Assigned Managed Identity
#
# This script ensures a user-assigned managed identity exists in the resource group.
# It can detect existing identities or create a new one.
#
# Usage:
# # Auto-create managed identity
# RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" \
# MANAGED_IDENTITY_NAME="id-appgw" ./53-setup-managed-identity.sh
#
# # Detect only (fail if not exists)
# RESOURCE_GROUP="rg-subnet-calc" \
# MANAGED_IDENTITY_NAME="id-appgw" \
# MANAGED_IDENTITY_CREATE=false \
# ./53-setup-managed-identity.sh
#
# Input (environment variables required):
# RESOURCE_GROUP - Azure resource group name
# MANAGED_IDENTITY_NAME - Name for the managed identity
#
# Input (environment variables optional):
# LOCATION - Azure region (required if creating new identity)
# MANAGED_IDENTITY_CREATE - Create if not exists (default: true)
# MANAGED_IDENTITY_DESCRIPTION - Description tag (default: "Managed by script 53")
#
# Output (exported environment variables):
# MANAGED_IDENTITY_ID - Full resource ID of the managed identity
# MANAGED_IDENTITY_PRINCIPAL_ID - Principal ID for RBAC assignments
# MANAGED_IDENTITY_CLIENT_ID - Client ID of the managed identity
#
# Exit Codes:
# 0 - Success (managed identity ready)
# 1 - Error (missing env vars, creation failed, not found when create=false)

set -euo pipefail

# Colors and logging functions (skip if already defined by parent script)
if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  NC='\033[0m'

  log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
  log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
  log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
  log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  log_error "Usage: RESOURCE_GROUP=rg-name MANAGED_IDENTITY_NAME=id-name $0"
  exit 1
fi

if [[ -z "${MANAGED_IDENTITY_NAME:-}" ]]; then
  log_error "MANAGED_IDENTITY_NAME environment variable is required"
  log_error "Usage: RESOURCE_GROUP=rg-name MANAGED_IDENTITY_NAME=id-name $0"
  exit 1
fi

# Set defaults
MANAGED_IDENTITY_CREATE="${MANAGED_IDENTITY_CREATE:-true}"
MANAGED_IDENTITY_DESCRIPTION="${MANAGED_IDENTITY_DESCRIPTION:-Managed by script 53}"

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_step "Setting up user-assigned managed identity: ${MANAGED_IDENTITY_NAME}..."

# Check if managed identity exists
if ! az identity show \
  --name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --only-show-errors &>/dev/null; then

  if [[ "${MANAGED_IDENTITY_CREATE}" == "true" ]]; then
    # Validate LOCATION is provided for creation
    if [[ -z "${LOCATION:-}" ]]; then
      log_error "LOCATION environment variable is required for creating managed identity"
      log_error "Usage: RESOURCE_GROUP=rg-name LOCATION=region MANAGED_IDENTITY_NAME=id-name $0"
      exit 1
    fi

    log_info "Creating managed identity: ${MANAGED_IDENTITY_NAME} in ${LOCATION}..."

    if ! az identity create \
      --name "${MANAGED_IDENTITY_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --location "${LOCATION}" \
      --tags description="${MANAGED_IDENTITY_DESCRIPTION}" \
      --output none; then
      log_error "Failed to create managed identity"
      exit 1
    fi

    log_info "Managed identity created successfully"
  else
    log_error "Managed identity '${MANAGED_IDENTITY_NAME}' not found"
    log_error "MANAGED_IDENTITY_CREATE is set to false"
    log_error ""
    log_error "Options:"
    log_error " 1. Set MANAGED_IDENTITY_CREATE=true to auto-create"
    log_error " 2. Create manually via Azure Portal or CLI"
    exit 1
  fi
else
  log_info "Found existing managed identity: ${MANAGED_IDENTITY_NAME}"
fi

# Get identity details
IDENTITY_INFO=$(az identity show \
  --name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "{id:id, principalId:principalId, clientId:clientId}" -o json)

MANAGED_IDENTITY_ID=$(echo "${IDENTITY_INFO}" | jq -r '.id')
MANAGED_IDENTITY_PRINCIPAL_ID=$(echo "${IDENTITY_INFO}" | jq -r '.principalId')
MANAGED_IDENTITY_CLIENT_ID=$(echo "${IDENTITY_INFO}" | jq -r '.clientId')

log_info "Managed identity ready: ${MANAGED_IDENTITY_NAME}"
log_info "Resource ID: ${MANAGED_IDENTITY_ID}"
log_info "Principal ID: ${MANAGED_IDENTITY_PRINCIPAL_ID}"
log_info "Client ID: ${MANAGED_IDENTITY_CLIENT_ID}"

# Export for caller scripts
export MANAGED_IDENTITY_NAME
export MANAGED_IDENTITY_ID
export MANAGED_IDENTITY_PRINCIPAL_ID
export MANAGED_IDENTITY_CLIENT_ID

log_info "Exported MANAGED_IDENTITY_* variables"
