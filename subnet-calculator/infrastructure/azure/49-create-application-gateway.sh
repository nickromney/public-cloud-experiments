#!/usr/bin/env bash
#
# Create Azure Application Gateway for Static Web App Private Endpoint
#
# This script creates an Application Gateway to provide public HTTPS access
# to a Static Web App that is configured with a private endpoint. The Application
# Gateway sits in the VNet and routes public traffic to the private SWA endpoint.
#
# Usage:
#   # Interactive mode (prompts for values)
#   ./49-create-application-gateway.sh
#
#   # Specify all parameters
#   STATIC_WEB_APP_NAME="swa-subnet-calc-private" \
#   RESOURCE_GROUP="rg-subnet-calc" \
#   VNET_NAME="vnet-platform" \
#   ./49-create-application-gateway.sh
#
# Parameters:
#   STATIC_WEB_APP_NAME   - Name of the Static Web App
#   RESOURCE_GROUP        - Resource group containing the resources
#   VNET_NAME             - Name of the VNet
#   APPGW_SUBNET_NAME     - Application Gateway subnet name (default: snet-appgateway)
#   APPGW_SUBNET_PREFIX   - Application Gateway subnet CIDR (default: 10.100.0.32/27)
#   APPGW_NAME            - Application Gateway name (default: agw-{swa-name})
#   APPGW_SKU             - SKU (default: Standard_v2, options: Standard_v2, WAF_v2)
#   CUSTOM_DOMAIN         - Custom domain for HTTPS (optional)
#   LOCATION              - Azure region (auto-detected from resource group if not set)
#
# Requirements:
#   - Azure CLI logged in (az login)
#   - Static Web App must exist with a private endpoint
#   - VNet must exist
#   - Application Gateway subnet will be created if it doesn't exist
#   - User must have permissions to create network resources
#
# Created Resources:
#   - Application Gateway subnet (if not exists)
#   - Public IP (Standard SKU for v2)
#   - Application Gateway (Standard_v2 or WAF_v2)
#   - Backend pool (SWA private endpoint IP)
#   - HTTP listener (port 80)
#   - Routing rule
#
# Architecture:
#   Internet → Public IP → App Gateway → SWA Private Endpoint → SWA
#
# Costs:
#   - Standard_v2: ~$0.443/hour (~$320/month) + data processing
#   - WAF_v2: ~$0.583/hour (~$421/month) + data processing
#   - Public IP: ~$3.65/month
#   - Total: ~$324-425/month
#
# Notes:
#   - Application Gateway v2 requires minimum /27 subnet (32 addresses)
#   - Recommended /24 for production with autoscaling
#   - This script configures HTTP (port 80) by default
#   - For HTTPS, you need to provide a certificate (see --custom-domain)
#   - The SWA must already have a private endpoint configured
#
# Reference:
#   https://learn.microsoft.com/en-us/azure/application-gateway/overview

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
  log_info "STATIC_WEB_APP_NAME not set. Looking for Static Web Apps..."
  SWA_COUNT=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${SWA_COUNT}" -eq 0 ]]; then
    log_error "No Static Web Apps found in resource group ${RESOURCE_GROUP}"
    exit 1
  elif [[ "${SWA_COUNT}" -eq 1 ]]; then
    STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    log_info "Auto-detected Static Web App: ${STATIC_WEB_APP_NAME}"
  else
    log_warn "Multiple Static Web Apps found:"
    mapfile -t SWA_NAMES < <(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv)
    PS3="Select a Static Web App: "
    select STATIC_WEB_APP_NAME in "${SWA_NAMES[@]}"; do
      if [[ -n "${STATIC_WEB_APP_NAME}" ]]; then
        break
      fi
    done
    log_info "Selected: ${STATIC_WEB_APP_NAME}"
  fi
fi

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  log_info "Detected region from resource group: ${LOCATION}"
fi

# Check if VNET_NAME is set, otherwise prompt
if [[ -z "${VNET_NAME:-}" ]]; then
  log_error "VNET_NAME not set"
  log_error "Please specify the VNet name"
  log_error ""
  log_error "Example:"
  log_error "  VNET_NAME=\"vnet-platform\" ./49-create-application-gateway.sh"
  exit 1
fi

# Configuration with defaults
readonly APPGW_SUBNET_NAME="${APPGW_SUBNET_NAME:-snet-appgateway}"
readonly APPGW_SUBNET_PREFIX="${APPGW_SUBNET_PREFIX:-10.100.0.32/27}"
readonly APPGW_NAME="${APPGW_NAME:-agw-${STATIC_WEB_APP_NAME}}"
readonly APPGW_SKU="${APPGW_SKU:-Standard_v2}"
readonly PUBLIC_IP_NAME="pip-${APPGW_NAME}"

log_info ""
log_info "========================================="
log_info "Application Gateway Configuration"
log_info "========================================="
log_info "Resource Group:       ${RESOURCE_GROUP}"
log_info "Static Web App:       ${STATIC_WEB_APP_NAME}"
log_info "VNet:                 ${VNET_NAME}"
log_info "AppGW Subnet:         ${APPGW_SUBNET_NAME} (${APPGW_SUBNET_PREFIX})"
log_info "Application Gateway:  ${APPGW_NAME}"
log_info "SKU:                  ${APPGW_SKU}"
log_info "Public IP:            ${PUBLIC_IP_NAME}"
log_info ""

# Verify Static Web App exists
log_step "Verifying Static Web App exists..."
if ! SWA_ID=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "Static Web App ${STATIC_WEB_APP_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "Static Web App found: ${SWA_ID}"

# Get SWA default hostname
SWA_HOSTNAME=$(az staticwebapp show \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "defaultHostname" -o tsv)

log_info "SWA Hostname: ${SWA_HOSTNAME}"

# Find the private endpoint for the SWA
log_step "Finding SWA private endpoint..."
PE_NAME="pe-${STATIC_WEB_APP_NAME}"

if ! az network private-endpoint show \
  --name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv &>/dev/null; then
  log_error "Private endpoint ${PE_NAME} not found"
  log_error "The Static Web App must have a private endpoint configured first"
  log_error "Run: ./48-create-private-endpoint-swa.sh"
  exit 1
fi

# Get private endpoint IP from DNS zone group (more reliable than customDnsConfigs)
log_step "Retrieving SWA private IP from DNS zone group..."
SWA_PRIVATE_IP=$(az network private-endpoint dns-zone-group show \
  --name "default" \
  --endpoint-name "${PE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]" -o tsv 2>/dev/null)

if [[ -z "${SWA_PRIVATE_IP}" ]]; then
  log_error "Could not retrieve private IP for SWA private endpoint"
  log_error "Ensure DNS zone group is configured on the private endpoint"
  log_error ""
  log_error "Check DNS zone group:"
  log_error "  az network private-endpoint dns-zone-group show \\"
  log_error "    --name default \\"
  log_error "    --endpoint-name ${PE_NAME} \\"
  log_error "    --resource-group ${RESOURCE_GROUP}"
  exit 1
fi

log_info "SWA Private Endpoint: ${PE_NAME}"
log_info "SWA Private IP: ${SWA_PRIVATE_IP}"

# Verify VNet exists
log_step "Verifying VNet exists..."
if ! VNET_ID=$(az network vnet show \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv 2>/dev/null); then
  log_error "VNet ${VNET_NAME} not found in ${RESOURCE_GROUP}"
  exit 1
fi
log_info "VNet found: ${VNET_ID}"

# Check if Application Gateway subnet exists, create if not
log_step "Checking for Application Gateway subnet..."
if az network vnet subnet show \
  --name "${APPGW_SUBNET_NAME}" \
  --vnet-name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Application Gateway subnet ${APPGW_SUBNET_NAME} already exists"
else
  log_info "Creating Application Gateway subnet ${APPGW_SUBNET_NAME}..."
  az network vnet subnet create \
    --name "${APPGW_SUBNET_NAME}" \
    --vnet-name "${VNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --address-prefix "${APPGW_SUBNET_PREFIX}" \
    --output none

  log_info "Application Gateway subnet created"
fi

# Check if Application Gateway already exists
log_step "Checking for existing Application Gateway..."
if az network application-gateway show \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Application Gateway ${APPGW_NAME} already exists"
  log_error "Delete it first or use a different name"
  exit 1
fi

# Create Public IP for Application Gateway (must be Standard SKU for v2)
log_step "Creating public IP for Application Gateway..."
if az network public-ip show \
  --name "${PUBLIC_IP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_info "Public IP ${PUBLIC_IP_NAME} already exists"
else
  az network public-ip create \
    --name "${PUBLIC_IP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard \
    --allocation-method Static \
    --output none

  log_info "Public IP created: ${PUBLIC_IP_NAME}"
fi

# Get public IP address for display
PUBLIC_IP_ADDRESS=$(az network public-ip show \
  --name "${PUBLIC_IP_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query ipAddress -o tsv)

log_info "Public IP Address: ${PUBLIC_IP_ADDRESS}"

# Create Application Gateway
log_step "Creating Application Gateway (this may take 5-10 minutes)..."
log_info "This is a long-running operation. Please wait..."

az network application-gateway create \
  --name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku "${APPGW_SKU}" \
  --capacity 2 \
  --vnet-name "${VNET_NAME}" \
  --subnet "${APPGW_SUBNET_NAME}" \
  --public-ip-address "${PUBLIC_IP_NAME}" \
  --http-settings-cookie-based-affinity Disabled \
  --http-settings-port 443 \
  --http-settings-protocol Https \
  --frontend-port 80 \
  --servers "${SWA_PRIVATE_IP}" \
  --priority 100 \
  --output none

log_info "Application Gateway created: ${APPGW_NAME}"

# Update backend pool with proper hostname
log_step "Configuring backend pool with SWA hostname..."
az network application-gateway address-pool update \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name appGatewayBackendPool \
  --servers "${SWA_PRIVATE_IP}" \
  --output none

# Update HTTP settings to use the SWA hostname
log_step "Configuring HTTP settings for SWA..."
az network application-gateway http-settings update \
  --gateway-name "${APPGW_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name appGatewayBackendHttpSettings \
  --port 443 \
  --protocol Https \
  --cookie-based-affinity Disabled \
  --timeout 30 \
  --host-name "${SWA_HOSTNAME}" \
  --output none

log_info "Application Gateway configured"

# Summary
log_info ""
log_info "========================================="
log_info "Application Gateway Created!"
log_info "========================================="
log_info "Application Gateway:  ${APPGW_NAME}"
log_info "Public IP:            ${PUBLIC_IP_ADDRESS}"
log_info "Backend (SWA):        ${SWA_PRIVATE_IP} (${SWA_HOSTNAME})"
log_info ""
log_info "Access URLs:"
log_info "  HTTP:  http://${PUBLIC_IP_ADDRESS}"
log_info ""
log_info "Architecture:"
log_info "  Internet → ${PUBLIC_IP_ADDRESS}:80 → App Gateway → ${SWA_PRIVATE_IP}:443 → SWA"
log_info ""
log_info "Next Steps:"
log_info "1. Test HTTP access:"
log_info "   curl -L http://${PUBLIC_IP_ADDRESS}"
log_info ""
log_info "2. (Optional) Configure custom domain with DNS:"
log_info "   Create A record: your-domain.com → ${PUBLIC_IP_ADDRESS}"
log_info ""
log_info "3. (Optional) Add HTTPS listener with certificate:"
log_info "   az network application-gateway ssl-cert create ..."
log_info "   az network application-gateway frontend-port create --port 443 ..."
log_info "   az network application-gateway http-listener create --frontend-port 443 ..."
log_info ""
log_info "Monthly Cost Estimate:"
log_info "  - Application Gateway (${APPGW_SKU}): ~\$320-421/month"
log_info "  - Public IP: ~\$3.65/month"
log_info "  - Data processing: Variable"
log_info ""
log_info "To remove the Application Gateway:"
log_info "  az network application-gateway delete \\"
log_info "    --name ${APPGW_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP}"
log_info ""
