#!/usr/bin/env bash
#
# 54-add-https-listener-named.sh - Add Named HTTPS Listener to Application Gateway
#
# This script adds a named HTTPS listener with certificate to an existing Application Gateway.
# Unlike script 50 (which replaces HTTP with HTTPS for single app), this script ADDS
# a new listener alongside existing ones, enabling multi-stack AppGW reuse.
#
# Use Cases:
#   - Stack 17: Add listener for static-swa-apim.publiccloudexperiments.net
#   - Stack 18: Add listener for static-swa-apim-private.publiccloudexperiments.net
#   - Multiple stacks sharing same AppGW with different domains
#
# Usage:
#   RESOURCE_GROUP="rg-subnet-calc" \
#   APPGW_NAME="agw-swa-subnet-calc-private-endpoint" \
#   LISTENER_NAME="swa-apim-listener" \
#   CUSTOM_DOMAIN="static-swa-apim.publiccloudexperiments.net" \
#   BACKEND_FQDN="swa-subnet-calc-apim.privatelink.3.azurestaticapps.net" \
#   ./54-add-https-listener-named.sh
#
# Required Environment Variables:
#   RESOURCE_GROUP  - Resource group name
#   APPGW_NAME      - Application Gateway name
#   LISTENER_NAME   - Unique listener name (e.g., "swa-apim-listener")
#   CUSTOM_DOMAIN   - Domain for certificate and SNI (e.g., "api.example.com")
#   BACKEND_FQDN    - Backend hostname or IP
#
# Optional Environment Variables:
#   KEY_VAULT_NAME        - Key Vault name (auto-detected if single instance)
#   BACKEND_POOL_NAME     - Backend pool name (default: listener-name-backend)
#   HTTP_SETTINGS_NAME    - HTTP settings name (default: listener-name-http-settings)
#   ROUTING_RULE_NAME     - Routing rule name (default: listener-name-rule)
#   ROUTING_PRIORITY      - Rule priority (default: auto-increment from highest existing)
#   BACKEND_PORT          - Backend port (default: 443)
#   BACKEND_PROTOCOL      - Backend protocol (default: Https)
#   FORCE_CERT_REGEN      - Force certificate regeneration (default: false)
#
# Exit Codes:
#   0 - Success (listener added)
#   1 - Error (validation failed, creation failed)

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
if ! command -v az &>/dev/null; then
  log_error "Azure CLI not found"
  exit 1
fi

if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_error "RESOURCE_GROUP environment variable is required"
  exit 1
fi

if [[ -z "${APPGW_NAME:-}" ]]; then
  log_error "APPGW_NAME environment variable is required"
  exit 1
fi

if [[ -z "${LISTENER_NAME:-}" ]]; then
  log_error "LISTENER_NAME environment variable is required"
  log_error "Example: LISTENER_NAME='swa-apim-listener' $0"
  exit 1
fi

if [[ -z "${CUSTOM_DOMAIN:-}" ]]; then
  log_error "CUSTOM_DOMAIN environment variable is required"
  log_error "Example: CUSTOM_DOMAIN='static-swa-apim.publiccloudexperiments.net' $0"
  exit 1
fi

if [[ -z "${BACKEND_FQDN:-}" ]]; then
  log_error "BACKEND_FQDN environment variable is required"
  log_error "Example: BACKEND_FQDN='swa-name.privatelink.3.azurestaticapps.net' $0"
  exit 1
fi

# Configuration with defaults
readonly BACKEND_POOL_NAME="${BACKEND_POOL_NAME:-${LISTENER_NAME}-backend}"
readonly HTTP_SETTINGS_NAME="${HTTP_SETTINGS_NAME:-${LISTENER_NAME}-http-settings}"
readonly ROUTING_RULE_NAME="${ROUTING_RULE_NAME:-${LISTENER_NAME}-rule}"
readonly BACKEND_PORT="${BACKEND_PORT:-443}"
readonly BACKEND_PROTOCOL="${BACKEND_PROTOCOL:-Https}"
readonly CERT_NAME="${LISTENER_NAME}-cert"
readonly SECRET_NAME="${LISTENER_NAME}-ssl-cert"

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  AppGW:          ${APPGW_NAME}"
log_info "  Listener:       ${LISTENER_NAME}"
log_info "  Domain:         ${CUSTOM_DOMAIN}"
log_info "  Backend FQDN:   ${BACKEND_FQDN}"
log_info "  Backend Pool:   ${BACKEND_POOL_NAME}"
log_info "  HTTP Settings:  ${HTTP_SETTINGS_NAME}"
log_info "  Routing Rule:   ${ROUTING_RULE_NAME}"
log_info ""

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Resource group '${RESOURCE_GROUP}' not found"
  exit 1
fi

# Verify AppGW exists
log_step "Verifying Application Gateway..."
if ! APPGW_STATE=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "provisioningState" -o tsv 2>/dev/null); then
  log_error "Application Gateway '${APPGW_NAME}' not found"
  exit 1
fi

if [[ "${APPGW_STATE}" != "Succeeded" ]]; then
  log_error "Application Gateway state: ${APPGW_STATE}"
  log_error "Wait for provisioning to complete"
  exit 1
fi

log_info "Application Gateway is ready"

# Check if listener already exists
log_step "Checking for existing listener..."
if az network application-gateway http-listener show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${LISTENER_NAME}" &>/dev/null; then
  log_warn "Listener '${LISTENER_NAME}' already exists"
  log_info "Skipping listener creation"
  exit 0
fi

# Detect or validate Key Vault
log_step "Detecting Key Vault..."
if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
  KV_COUNT=$(az keyvault list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${KV_COUNT}" -eq 0 ]]; then
    log_error "No Key Vault found in ${RESOURCE_GROUP}"
    log_error "Create one first: ./51-setup-keyvault.sh"
    exit 1
  elif [[ "${KV_COUNT}" -eq 1 ]]; then
    KEY_VAULT_NAME=$(az keyvault list \
      --resource-group "${RESOURCE_GROUP}" \
      --query "[0].name" -o tsv)
    log_info "Auto-detected Key Vault: ${KEY_VAULT_NAME}"
  else
    log_error "Multiple Key Vaults found. Specify: KEY_VAULT_NAME='kv-name' $0"
    exit 1
  fi
fi

KEY_VAULT_ID=$(az keyvault show \
  --name "${KEY_VAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

log_info "Using Key Vault: ${KEY_VAULT_NAME}"

# Generate self-signed certificate and upload to Key Vault
log_step "Setting up SSL certificate..."

SKIP_CERT_GENERATION=false
if az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" &>/dev/null; then

  log_warn "Certificate '${SECRET_NAME}' already exists in Key Vault"

  if [[ "${FORCE_CERT_REGEN:-false}" == "true" ]]; then
    log_warn "FORCE_CERT_REGEN=true, regenerating certificate..."
  else
    log_info "Reusing existing certificate"
    SKIP_CERT_GENERATION=true
  fi
fi

if [[ "${SKIP_CERT_GENERATION}" == "false" ]]; then
  log_info "Generating self-signed certificate for ${CUSTOM_DOMAIN}..."

  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TEMP_DIR}"' EXIT

  CERT_KEY="${TEMP_DIR}/cert.key"
  CERT_CRT="${TEMP_DIR}/cert.crt"
  CERT_PFX="${TEMP_DIR}/cert.pfx"
  CERT_PASSWORD="$(openssl rand -base64 32)"

  # Generate certificate
  openssl req -x509 -newkey rsa:4096 -sha256 -days 365 \
    -nodes -keyout "${CERT_KEY}" -out "${CERT_CRT}" \
    -subj "/CN=${CUSTOM_DOMAIN}" \
    -addext "subjectAltName=DNS:${CUSTOM_DOMAIN}" \
    2>/dev/null

  # Convert to PFX
  openssl pkcs12 -export \
    -out "${CERT_PFX}" \
    -inkey "${CERT_KEY}" \
    -in "${CERT_CRT}" \
    -passout "pass:${CERT_PASSWORD}" \
    2>/dev/null

  # Encode PFX to base64
  CERT_BASE64=$(base64 < "${CERT_PFX}" | tr -d '\n')

  # Store in Key Vault
  log_info "Storing certificate in Key Vault as: ${SECRET_NAME}"
  az keyvault secret set \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${SECRET_NAME}" \
    --value "${CERT_BASE64}" \
    --description "SSL cert for ${CUSTOM_DOMAIN} (listener: ${LISTENER_NAME})" \
    --output none

  log_info "Certificate stored successfully"
fi

# Ensure AppGW managed identity has access to Key Vault
log_step "Configuring managed identity access..."

MANAGED_IDENTITY_ID=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "identity.userAssignedIdentities | keys(@) | [0]" -o tsv 2>/dev/null || echo "")

if [[ -z "${MANAGED_IDENTITY_ID}" ]]; then
  log_error "Application Gateway does not have a managed identity"
  log_error "Run script 53 first to create managed identity"
  exit 1
fi

MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
  --ids "${MANAGED_IDENTITY_ID}" \
  --query principalId -o tsv)

# Check if RBAC role already assigned
EXISTING_ROLE=$(az role assignment list \
  --assignee "${MANAGED_IDENTITY_PRINCIPAL_ID}" \
  --scope "${KEY_VAULT_ID}" \
  --query "[?roleDefinitionName=='Key Vault Secrets User'].id" -o tsv 2>/dev/null || echo "")

if [[ -n "${EXISTING_ROLE}" ]]; then
  log_info "RBAC role assignment already exists"
else
  log_info "Assigning 'Key Vault Secrets User' role..."
  az role assignment create \
    --assignee "${MANAGED_IDENTITY_PRINCIPAL_ID}" \
    --role "Key Vault Secrets User" \
    --scope "${KEY_VAULT_ID}" \
    --output none

  log_info "Waiting 30 seconds for RBAC propagation..."
  sleep 30
fi

# Get certificate secret ID (versionless for auto-renewal)
log_step "Retrieving certificate secret ID..."
SECRET_ID=$(az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --query "id" -o tsv)

# Remove version from secret ID
SECRET_ID="${SECRET_ID%/*}"
log_info "Certificate secret ID: ${SECRET_ID}"

# Create HTTPS frontend port (443) if it doesn't exist
log_step "Creating HTTPS frontend port..."
if az network application-gateway frontend-port show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "appGatewayHttpsPort" &>/dev/null; then
  log_info "HTTPS port already exists"
else
  az network application-gateway frontend-port create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "appGatewayHttpsPort" \
    --port 443 \
    --output none
  log_info "HTTPS port created"
fi

# Add SSL certificate to AppGW
log_step "Adding SSL certificate..."
if az network application-gateway ssl-cert show \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CERT_NAME}" &>/dev/null; then
  log_info "Certificate already exists on AppGW"
else
  az network application-gateway ssl-cert create \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CERT_NAME}" \
    --key-vault-secret-id "${SECRET_ID}" \
    --output none
  log_info "Certificate added to AppGW"
fi

# Create HTTPS listener
log_step "Creating HTTPS listener..."
az network application-gateway http-listener create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${LISTENER_NAME}" \
  --frontend-port "appGatewayHttpsPort" \
  --ssl-cert "${CERT_NAME}" \
  --host-name "${CUSTOM_DOMAIN}" \
  --output none

log_info "HTTPS listener created: ${LISTENER_NAME}"

# Create backend pool
log_step "Creating backend pool..."
az network application-gateway address-pool create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${BACKEND_POOL_NAME}" \
  --servers "${BACKEND_FQDN}" \
  --output none

log_info "Backend pool created: ${BACKEND_POOL_NAME}"

# Create HTTP settings
log_step "Creating HTTP settings..."
az network application-gateway http-settings create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${HTTP_SETTINGS_NAME}" \
  --port "${BACKEND_PORT}" \
  --protocol "${BACKEND_PROTOCOL}" \
  --cookie-based-affinity Disabled \
  --timeout 30 \
  --host-name "${CUSTOM_DOMAIN}" \
  --output none

log_info "HTTP settings created: ${HTTP_SETTINGS_NAME}"

# Determine routing rule priority
log_step "Determining routing rule priority..."
if [[ -n "${ROUTING_PRIORITY:-}" ]]; then
  PRIORITY="${ROUTING_PRIORITY}"
  log_info "Using specified priority: ${PRIORITY}"
else
  # Get highest existing priority and add 10
  HIGHEST_PRIORITY=$(az network application-gateway rule list \
    --gateway-name "${APPGW_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "max([].priority)" -o tsv 2>/dev/null || echo "0")

  PRIORITY=$((HIGHEST_PRIORITY + 10))
  log_info "Auto-calculated priority: ${PRIORITY} (highest existing: ${HIGHEST_PRIORITY})"
fi

# Create routing rule
log_step "Creating routing rule..."
az network application-gateway rule create \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ROUTING_RULE_NAME}" \
  --http-listener "${LISTENER_NAME}" \
  --address-pool "${BACKEND_POOL_NAME}" \
  --http-settings "${HTTP_SETTINGS_NAME}" \
  --rule-type Basic \
  --priority "${PRIORITY}" \
  --output none

log_info "Routing rule created: ${ROUTING_RULE_NAME}"

# Get AppGW public IP
PUBLIC_IP=$(az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "frontendIPConfigurations[0].publicIPAddress.id" -o tsv | \
  xargs -I {} az network public-ip show --ids {} --query ipAddress -o tsv)

log_info ""
log_info "✓ HTTPS Listener Added Successfully!"
log_info ""
log_info "========================================="
log_info "Listener Configuration"
log_info "========================================="
log_info "Listener Name:    ${LISTENER_NAME}"
log_info "Domain:           ${CUSTOM_DOMAIN}"
log_info "Backend Pool:     ${BACKEND_POOL_NAME}"
log_info "Backend FQDN:     ${BACKEND_FQDN}"
log_info "Routing Priority: ${PRIORITY}"
log_info ""
log_info "AppGW Public IP:  ${PUBLIC_IP}"
log_info ""
log_info "Next Steps:"
log_info "1. Configure DNS A record:"
log_info "   ${CUSTOM_DOMAIN} → ${PUBLIC_IP}"
log_info ""
log_info "2. Test access (after DNS propagation):"
log_info "   curl -v https://${CUSTOM_DOMAIN}"
log_info ""
