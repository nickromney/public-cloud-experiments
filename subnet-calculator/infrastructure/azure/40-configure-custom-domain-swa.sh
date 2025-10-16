#!/usr/bin/env bash
#
# Configure custom domain for Azure Static Web App
# - Validates domain ownership via TXT record
# - Configures custom domain
# - Free SSL/TLS certificate (auto-provisioned)
# - Optionally sets as default domain (redirects traffic)
#
# Usage:
#   CUSTOM_DOMAIN=www.example.com ./40-configure-custom-domain-swa.sh

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory and source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/selection-utils.sh
source "${SCRIPT_DIR}/lib/selection-utils.sh"

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

# Auto-detect or prompt for STATIC_WEB_APP_NAME
if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
  log_info "STATIC_WEB_APP_NAME not set. Looking for Static Web Apps in ${RESOURCE_GROUP}..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in ${RESOURCE_GROUP}"
    log_error "Create one first with: ./00-static-web-app.sh"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Found Static Web App: ${STATIC_WEB_APP_NAME}"
    read -r -p "Configure custom domain for this app? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_info "Cancelled"
      exit 0
    fi
  else
    log_info "Found ${SWA_COUNT} Static Web Apps in ${RESOURCE_GROUP}:"
    STATIC_WEB_APP_NAME=$(select_static_web_app "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
  fi
fi

# Prompt for CUSTOM_DOMAIN if not set
if [[ -z "${CUSTOM_DOMAIN:-}" ]]; then
  log_error "CUSTOM_DOMAIN environment variable is required"
  log_error "Example: CUSTOM_DOMAIN=www.example.com ./40-configure-custom-domain-swa.sh"
  exit 1
fi

# Configuration with defaults
readonly SET_AS_DEFAULT="${SET_AS_DEFAULT:-true}"

# Check if Static Web Apps extension is installed
if ! az staticwebapp --help &>/dev/null; then
  log_warn "Azure CLI Static Web Apps extension not found. Installing..."
  az extension add --name staticwebapp --yes
fi

# Verify Static Web App exists
if ! az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found"
  log_error "Run 00-static-web-app.sh first to create it"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
log_info "  Custom Domain: ${CUSTOM_DOMAIN}"
log_info "  Set as Default: ${SET_AS_DEFAULT}"

# Get Static Web App hostname
SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query defaultHostname -o tsv)

log_info ""
log_info "========================================="
log_info "STEP 1: DNS Configuration Required"
log_info "========================================="
log_info ""
log_info "Before continuing, you MUST configure these DNS records:"
log_info ""
log_info "1. TXT record for domain validation:"
log_info "   Name:  _dnsauth.${CUSTOM_DOMAIN}"
log_info "   Type:  TXT"
log_info "   Value: <validation-token-from-azure>"
log_info ""
log_info "2. CNAME record to point to Static Web App:"
log_info "   Name:  ${CUSTOM_DOMAIN}"
log_info "   Type:  CNAME"
log_info "   Value: ${SWA_HOSTNAME}"
log_info ""
log_info "To get the validation token, we'll add the custom domain first."
log_info "Azure will provide the token, then you configure DNS, then we validate."
log_info ""
read -p "Press Enter to continue once you understand these requirements..." -r

# Check if custom domain already exists
if az staticwebapp hostname show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${CUSTOM_DOMAIN}" &>/dev/null; then
  log_warn "Custom domain ${CUSTOM_DOMAIN} already configured for ${STATIC_WEB_APP_NAME}"

  # Check if it should be set as default
  if [[ "${SET_AS_DEFAULT}" == "true" ]]; then
    log_info "Setting ${CUSTOM_DOMAIN} as default domain..."
    az staticwebapp hostname set \
      --name "${STATIC_WEB_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --hostname "${CUSTOM_DOMAIN}" \
      --output none

    log_info "✓ ${CUSTOM_DOMAIN} set as default domain"
    log_info "All traffic will be redirected to https://${CUSTOM_DOMAIN}"
  fi

  exit 0
fi

# Add custom domain (this generates the validation token)
log_info ""
log_info "========================================="
log_info "STEP 2: Adding Custom Domain"
log_info "========================================="
log_info ""
log_info "Adding custom domain ${CUSTOM_DOMAIN}..."

# Add the custom domain - this will provide the validation token
az staticwebapp hostname set \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${CUSTOM_DOMAIN}" \
  --output none || {
    log_error "Failed to add custom domain"
    log_error "This may be because:"
    log_error "  1. CNAME record not configured yet"
    log_error "  2. Domain is already in use by another resource"
    log_error "  3. Static Web App SKU doesn't support custom domains"
    exit 1
  }

log_info "✓ Custom domain added"

# Get validation token
log_info ""
log_info "Retrieving validation token..."

# The validation token is shown when you query the hostname
VALIDATION_INFO=$(az staticwebapp hostname show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --hostname "${CUSTOM_DOMAIN}" \
  --query "[validationToken, status]" -o tsv)

VALIDATION_TOKEN=$(echo "${VALIDATION_INFO}" | awk '{print $1}')
VALIDATION_STATUS=$(echo "${VALIDATION_INFO}" | awk '{print $2}')

log_info ""
log_info "========================================="
log_info "STEP 3: Configure DNS Records"
log_info "========================================="
log_info ""
log_info "1. Add TXT record for validation:"
log_info "   Name:  _dnsauth.${CUSTOM_DOMAIN}"
log_info "   Type:  TXT"
log_info "   Value: ${VALIDATION_TOKEN}"
log_info ""
log_info "2. Add CNAME record (if not already done):"
log_info "   Name:  ${CUSTOM_DOMAIN}"
log_info "   Type:  CNAME"
log_info "   Value: ${SWA_HOSTNAME}"
log_info ""
log_info "3. Wait for DNS propagation (1-48 hours, typically 5-15 minutes)"
log_info ""
log_info "Current validation status: ${VALIDATION_STATUS}"
log_info ""

# Offer to wait and validate
log_info "========================================="
log_info "STEP 4: Domain Validation"
log_info "========================================="
log_info ""
read -p "Have you configured the DNS records? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info ""
  log_info "Configuration paused. Once DNS is configured, you can:"
  log_info "  1. Re-run this script, or"
  log_info "  2. Manually validate via Azure Portal"
  log_info ""
  log_info "To check validation status:"
  log_info "  az staticwebapp hostname show \\"
  log_info "    --name ${STATIC_WEB_APP_NAME} \\"
  log_info "    --resource-group ${RESOURCE_GROUP} \\"
  log_info "    --hostname ${CUSTOM_DOMAIN} \\"
  log_info "    --query status -o tsv"
  exit 0
fi

# Wait for validation
log_info ""
log_info "Checking DNS propagation and validation status..."
log_info "This may take several minutes. Checking every 30 seconds..."
log_info ""

MAX_ATTEMPTS=20  # 10 minutes total
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))

  # Check validation status
  CURRENT_STATUS=$(az staticwebapp hostname show \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --hostname "${CUSTOM_DOMAIN}" \
    --query status -o tsv)

  log_info "Attempt $ATTEMPT/$MAX_ATTEMPTS: Status = ${CURRENT_STATUS}"

  if [[ "${CURRENT_STATUS}" == "Ready" ]]; then
    log_info "✓ Domain validated successfully!"
    break
  elif [[ "${CURRENT_STATUS}" == "Failed" ]]; then
    log_error "Domain validation failed"
    log_error "Check that DNS records are configured correctly"
    exit 1
  fi

  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    sleep 30
  fi
done

if [[ "${CURRENT_STATUS}" != "Ready" ]]; then
  log_warn "Domain validation still pending after 10 minutes"
  log_warn "DNS propagation may take longer. Check status manually:"
  log_warn "  az staticwebapp hostname show \\"
  log_warn "    --name ${STATIC_WEB_APP_NAME} \\"
  log_warn "    --resource-group ${RESOURCE_GROUP} \\"
  log_warn "    --hostname ${CUSTOM_DOMAIN} \\"
  log_warn "    --query status -o tsv"
  exit 0
fi

# Set as default domain if requested
if [[ "${SET_AS_DEFAULT}" == "true" ]]; then
  log_info ""
  log_info "========================================="
  log_info "STEP 5: Setting Default Domain"
  log_info "========================================="
  log_info ""
  log_info "Setting ${CUSTOM_DOMAIN} as default domain..."
  log_info "This will redirect all traffic from ${SWA_HOSTNAME} to ${CUSTOM_DOMAIN}"

  az staticwebapp hostname set \
    --name "${STATIC_WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --hostname "${CUSTOM_DOMAIN}" \
    --output none

  log_info "✓ ${CUSTOM_DOMAIN} set as default domain"
fi

log_info ""
log_info "========================================="
log_info "Custom Domain Configuration Complete!"
log_info "========================================="
log_info ""
log_info "Custom Domain: https://${CUSTOM_DOMAIN}"
log_info "Original URL: https://${SWA_HOSTNAME}"
log_info ""
if [[ "${SET_AS_DEFAULT}" == "true" ]]; then
  log_info "Traffic Redirect: ✓ Enabled"
  log_info "All requests to ${SWA_HOSTNAME} will redirect to ${CUSTOM_DOMAIN}"
else
  log_info "Traffic Redirect: ✗ Not enabled"
  log_info "Both URLs are accessible"
fi
log_info ""
log_info "SSL/TLS Certificate: Automatically provisioned by Azure (free)"
log_info ""
log_info "Note: The original *.azurestaticapps.net domain cannot be disabled,"
log_info "but traffic can be redirected to your custom domain."
log_info ""
log_info "To remove this custom domain:"
log_info "  az staticwebapp hostname delete \\"
log_info "    --name ${STATIC_WEB_APP_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP} \\"
log_info "    --hostname ${CUSTOM_DOMAIN}"
