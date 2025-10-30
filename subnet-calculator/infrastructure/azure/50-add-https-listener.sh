#!/usr/bin/env bash
#
# Add HTTPS listener to Application Gateway using Key Vault-stored certificate
# - Creates or finds existing Key Vault in resource group
# - Generates self-signed certificate for custom domain
# - Stores certificate in Key Vault with managed identity access
# - Replaces HTTP/80 listener with HTTPS/443 listener
# - Enables Cloudflare "Full" SSL/TLS mode (end-to-end encryption)
#
# Prerequisites:
#   - Application Gateway created (script 49)
#   - Custom domain configured on SWA
#   - OpenSSL installed (standard on Linux/macOS)
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" ./50-add-https-listener.sh
#   RESOURCE_GROUP="rg-subnet-calc" APPGW_NAME="agw-custom" ./50-add-https-listener.sh
#   RESOURCE_GROUP="rg-subnet-calc" FORCE_CERT_REGEN=true ./50-add-https-listener.sh
#
# Environment Variables:
#   RESOURCE_GROUP     (required) - Azure resource group
#   APPGW_NAME         (optional) - Application Gateway name (auto-detect if single)
#   CUSTOM_DOMAIN      (optional) - Custom domain for certificate (auto-detect from AppGW)
#   KEY_VAULT_NAME     (optional) - Key Vault name (required if multiple exist)
#   FORCE_CERT_REGEN   (optional) - Force certificate regeneration (default: false)

set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check prerequisites
check_prerequisites() {
  log_step "Checking prerequisites..."

  # Azure CLI
  if ! command -v az &>/dev/null; then
    log_error "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
  fi

  # Azure login
  if ! az account show &>/dev/null; then
    log_error "Not logged in to Azure. Run 'az login'"
    exit 1
  fi

  # OpenSSL
  if ! command -v openssl &>/dev/null; then
    log_error "OpenSSL not found. Install via package manager"
    exit 1
  fi

  log_info "Prerequisites check passed"
}

# Validate required environment variables
validate_environment() {
  log_step "Validating environment..."

  if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    log_error "RESOURCE_GROUP environment variable is required"
    log_error "Example: RESOURCE_GROUP='rg-subnet-calc' $0"
    exit 1
  fi

  # Verify resource group exists
  if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    log_error "Resource group '${RESOURCE_GROUP}' not found"
    exit 1
  fi

  # Get location from resource group
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Resource Group: ${RESOURCE_GROUP}"
  log_info "Location: ${LOCATION}"
}

# Main execution
main() {
  log_info "========================================="
  log_info "Add HTTPS Listener to Application Gateway"
  log_info "========================================="
  log_info ""

  check_prerequisites
  validate_environment

  log_info ""
  log_info "Script initialized successfully"
  log_info "Next: Detect Application Gateway..."
}

main "$@"
