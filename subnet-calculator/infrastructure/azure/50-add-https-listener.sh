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

# Detect or validate Application Gateway
detect_application_gateway() {
  log_step "Detecting Application Gateway..."

  if [[ -n "${APPGW_NAME:-}" ]]; then
    log_info "Using specified Application Gateway: ${APPGW_NAME}"
  else
    # Count AppGWs in resource group
    APPGW_COUNT=$(az network application-gateway list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "${APPGW_COUNT}" -eq 0 ]]; then
      log_error "No Application Gateway found in ${RESOURCE_GROUP}"
      log_error "Create one first with script 49"
      exit 1
    elif [[ "${APPGW_COUNT}" -eq 1 ]]; then
      APPGW_NAME=$(az network application-gateway list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[0].name" -o tsv)
      log_info "Auto-detected Application Gateway: ${APPGW_NAME}"
    else
      log_error "Multiple Application Gateways found in ${RESOURCE_GROUP}"
      log_error "Specify which one to use: APPGW_NAME='agw-name' $0"
      az network application-gateway list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].[name, provisioningState]" -o table
      exit 1
    fi
  fi

  # Verify AppGW exists and is running
  APPGW_STATE=$(az network application-gateway show \
    --name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")

  if [[ "${APPGW_STATE}" != "Succeeded" ]]; then
    log_error "Application Gateway '${APPGW_NAME}' state: ${APPGW_STATE}"
    log_error "Wait for provisioning to complete or check for errors"
    exit 1
  fi

  log_info "Application Gateway is ready: ${APPGW_NAME}"

  # Export for other functions
  export APPGW_NAME
}

# Detect custom domain from AppGW configuration
detect_custom_domain() {
  log_step "Detecting custom domain..."

  if [[ -n "${CUSTOM_DOMAIN:-}" ]]; then
    log_info "Using specified custom domain: ${CUSTOM_DOMAIN}"
    return
  fi

  # Try to get custom domain from HTTP settings host header
  CUSTOM_DOMAIN=$(az network application-gateway http-settings show \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name appGatewayBackendHttpSettings \
    --query "hostName" -o tsv 2>/dev/null || echo "")

  if [[ -z "${CUSTOM_DOMAIN}" ]]; then
    log_error "Could not detect custom domain from Application Gateway"
    log_error "Specify domain: CUSTOM_DOMAIN='your-domain.com' $0"
    exit 1
  fi

  log_info "Auto-detected custom domain: ${CUSTOM_DOMAIN}"
  export CUSTOM_DOMAIN
}

# Detect or create Key Vault (idempotent)
setup_key_vault() {
  log_step "Setting up Key Vault..."

  # Count Key Vaults in resource group
  KV_COUNT=$(az keyvault list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${KV_COUNT}" -eq 1 ]]; then
    KEY_VAULT_NAME=$(az keyvault list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
    log_info "Found existing Key Vault: ${KEY_VAULT_NAME}"

  elif [[ "${KV_COUNT}" -gt 1 ]]; then
    if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
      log_error "Multiple Key Vaults found in ${RESOURCE_GROUP}"
      log_error "Specify which one to use: KEY_VAULT_NAME='kv-name' $0"
      az keyvault list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].[name, properties.provisioningState]" -o table
      exit 1
    fi
    log_info "Using specified Key Vault: ${KEY_VAULT_NAME}"

  else
    # Create new Key Vault with unique name
    KV_SUFFIX=$(openssl rand -hex 2)  # 4 hex chars
    KEY_VAULT_NAME="kv-subnet-calc-${KV_SUFFIX}"

    log_info "Creating Key Vault: ${KEY_VAULT_NAME}..."
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
    exit 1
  fi

  # Get Key Vault resource ID for RBAC
  KEY_VAULT_ID=$(az keyvault show \
    --name "${KEY_VAULT_NAME}" \
    --query "id" -o tsv)

  log_info "Key Vault ready: ${KEY_VAULT_NAME}"

  export KEY_VAULT_NAME
  export KEY_VAULT_ID
}

# Generate self-signed certificate and upload to Key Vault (idempotent)
generate_and_upload_certificate() {
  log_step "Setting up SSL certificate..."

  readonly CERT_SECRET_NAME="appgw-ssl-cert"

  # Check if certificate already exists
  SKIP_CERT_GENERATION=false
  if az keyvault secret show \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${CERT_SECRET_NAME}" &>/dev/null; then

    log_warn "Certificate '${CERT_SECRET_NAME}' already exists in Key Vault"

    # Show expiration date
    CERT_EXPIRES=$(az keyvault secret show \
      --vault-name "${KEY_VAULT_NAME}" \
      --name "${CERT_SECRET_NAME}" \
      --query "attributes.expires" -o tsv 2>/dev/null || echo "")

    if [[ -n "${CERT_EXPIRES}" ]]; then
      log_info "Current certificate expires: ${CERT_EXPIRES}"
    fi

    # Check if forced regeneration
    if [[ "${FORCE_CERT_REGEN:-false}" == "true" ]]; then
      log_warn "FORCE_CERT_REGEN=true, regenerating certificate..."
    else
      read -r -p "Re-generate and update certificate? (y/N): " update_cert
      update_cert=${update_cert:-n}

      if [[ ! "${update_cert}" =~ ^[Yy]$ ]]; then
        log_info "Using existing certificate"
        SKIP_CERT_GENERATION=true
      fi
    fi
  fi

  if [[ "${SKIP_CERT_GENERATION}" == "true" ]]; then
    return
  fi

  # Create temporary directory for certificate files
  TEMP_CERT_DIR=$(mktemp -d)
  trap 'rm -rf "${TEMP_CERT_DIR}"' EXIT

  log_info "Generating self-signed certificate for ${CUSTOM_DOMAIN}..."

  # Generate private key and certificate
  if ! openssl req -x509 -newkey rsa:2048 \
    -keyout "${TEMP_CERT_DIR}/key.pem" \
    -out "${TEMP_CERT_DIR}/cert.pem" \
    -days 365 -nodes \
    -subj "/CN=${CUSTOM_DOMAIN}" \
    2>/dev/null; then
    log_error "Failed to generate certificate"
    exit 1
  fi

  log_info "Certificate generated successfully"

  # Generate random password for PFX
  CERT_PASSWORD=$(openssl rand -base64 16)

  # Export as PFX
  log_info "Exporting certificate as PFX..."
  if ! openssl pkcs12 -export \
    -out "${TEMP_CERT_DIR}/certificate.pfx" \
    -inkey "${TEMP_CERT_DIR}/key.pem" \
    -in "${TEMP_CERT_DIR}/cert.pem" \
    -password "pass:${CERT_PASSWORD}" \
    2>/dev/null; then
    log_error "Failed to export PFX"
    exit 1
  fi

  # Encode PFX as base64
  log_info "Uploading certificate to Key Vault..."

  # Detect OS for base64 encoding
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS (no -w flag)
    CERT_BASE64=$(base64 -i "${TEMP_CERT_DIR}/certificate.pfx")
  else
    # Linux (-w 0 for no line wrapping)
    CERT_BASE64=$(base64 -w 0 "${TEMP_CERT_DIR}/certificate.pfx")
  fi

  # Create JSON secret value (AppGW expects this format)
  CERT_JSON=$(cat <<EOF
{
  "data": "${CERT_BASE64}",
  "password": "${CERT_PASSWORD}"
}
EOF
)

  # Upload to Key Vault
  if az keyvault secret set \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${CERT_SECRET_NAME}" \
    --value "${CERT_JSON}" \
    --content-type "application/x-pkcs12" \
    --output none; then
    log_info "Certificate uploaded successfully to Key Vault"
  else
    log_error "Failed to upload certificate to Key Vault"
    exit 1
  fi

  # Export certificate expiration for summary
  CERT_EXPIRATION=$(date -v+365d +"%Y-%m-%d" 2>/dev/null || date -d "+365 days" +"%Y-%m-%d")
  export CERT_EXPIRATION
}

# Enable managed identity and grant Key Vault access (idempotent)
configure_managed_identity() {
  log_step "Configuring managed identity for Application Gateway..."

  # Check if system-assigned identity already enabled
  IDENTITY_PRINCIPAL_ID=$(az network application-gateway show \
    --name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "identity.principalId" -o tsv 2>/dev/null || echo "")

  if [[ -z "${IDENTITY_PRINCIPAL_ID}" ]] || [[ "${IDENTITY_PRINCIPAL_ID}" == "null" ]]; then
    log_info "Enabling system-assigned managed identity..."

    if ! az network application-gateway identity assign \
      --gateway-name "${APPGW_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --output none; then
      log_error "Failed to enable managed identity"
      exit 1
    fi

    # Retrieve identity principal ID
    IDENTITY_PRINCIPAL_ID=$(az network application-gateway show \
      --name "${APPGW_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query "identity.principalId" -o tsv)

    log_info "Managed identity enabled: ${IDENTITY_PRINCIPAL_ID}"
  else
    log_info "Managed identity already enabled: ${IDENTITY_PRINCIPAL_ID}"
  fi

  # Check if RBAC role assignment already exists
  EXISTING_ROLE=$(az role assignment list \
    --assignee "${IDENTITY_PRINCIPAL_ID}" \
    --role "Key Vault Secrets User" \
    --scope "${KEY_VAULT_ID}" \
    --query "[0].id" -o tsv 2>/dev/null || echo "")

  if [[ -n "${EXISTING_ROLE}" ]]; then
    log_info "RBAC role assignment already exists"
  else
    log_info "Assigning 'Key Vault Secrets User' role to managed identity..."

    if ! az role assignment create \
      --assignee "${IDENTITY_PRINCIPAL_ID}" \
      --role "Key Vault Secrets User" \
      --scope "${KEY_VAULT_ID}" \
      --output none; then
      log_error "Failed to assign RBAC role"
      exit 1
    fi

    log_info "RBAC role assigned successfully"
    log_info "Waiting 30 seconds for RBAC propagation..."
    sleep 30
  fi

  log_info "Managed identity configuration complete"
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
  log_info ""

  detect_application_gateway
  detect_custom_domain
  setup_key_vault
  generate_and_upload_certificate
  configure_managed_identity

  log_info ""
  log_info "Configuration:"
  log_info "  Application Gateway: ${APPGW_NAME}"
  log_info "  Custom Domain: ${CUSTOM_DOMAIN}"
  log_info "  Key Vault: ${KEY_VAULT_NAME}"
  log_info "  Resource Group: ${RESOURCE_GROUP}"
  log_info "  Location: ${LOCATION}"
}

main "$@"
