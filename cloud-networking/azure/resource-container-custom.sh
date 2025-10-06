#!/usr/bin/env bash
#
# Deploy Azure Container Instance with custom nginx page
# Shows subnet and IP information on the welcome page

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly LOCATION="${LOCATION:-eastus2}"
readonly VNET_NAME="${VNET_NAME:-vnet-simple}"
readonly SUBNET_NAME="${SUBNET_NAME:-snet-subnet1}"
readonly CONTAINER_NAME="${CONTAINER_NAME:-aci-test}"
readonly IMAGE="${IMAGE:-nginx:latest}"

# Subnet CIDR mapping (should match your network configuration)
declare -A SUBNET_CIDRS=(
  ["snet-subnet1"]="10.0.10.0/24"
  ["snet-subnet2"]="10.0.20.0/24"
  ["snet-subnet3"]="10.0.30.0/24"
  ["snet-subnet4"]="10.0.40.0/24"
)
readonly SUBNET_CIDR="${SUBNET_CIDRS[$SUBNET_NAME]:-unknown}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  VNET: ${VNET_NAME}"
log_info "  Subnet: ${SUBNET_NAME} (${SUBNET_CIDR})"
log_info "  Container: ${CONTAINER_NAME}"
log_info "  Image: ${IMAGE}"
log_info ""

# Create custom HTML generation script (base64 encoded to pass as command)
# shellcheck disable=SC2016  # Intentional: expressions in single quotes are for container runtime
CUSTOM_SCRIPT='#!/bin/sh
HOSTNAME=$(hostname)
PRIVATE_IP=$(hostname -i | awk '"'"'{print $1}'"'"')
cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>${SUBNET_NAME}</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .info-grid { display: grid; grid-template-columns: 200px 1fr; gap: 15px; margin-top: 20px; }
        .label { font-weight: bold; color: #666; }
        .value { color: #333; font-family: monospace; }
        .badge { background: #0078d4; color: white; padding: 5px 15px; border-radius: 4px; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure Container Instance</h1>
        <p><span class="badge">${SUBNET_NAME}</span></p>
        <div class="info-grid">
            <div class="label">Container:</div><div class="value">${CONTAINER_NAME}</div>
            <div class="label">Hostname:</div><div class="value">${HOSTNAME}</div>
            <div class="label">Private IP:</div><div class="value">${PRIVATE_IP}</div>
            <div class="label">Subnet:</div><div class="value">${SUBNET_NAME}</div>
            <div class="label">Subnet CIDR:</div><div class="value">${SUBNET_CIDR}</div>
            <div class="label">VNET:</div><div class="value">${VNET_NAME}</div>
        </div>
        <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">
        <p style="color: #666; font-size: 14px;">
            Demonstrating Azure networking. Container in ${SUBNET_NAME} (${SUBNET_CIDR}).
        </p>
    </div>
</body>
</html>
EOF
exec nginx -g "daemon off;"
'

# Create container instance with custom page
log_info "Creating container instance ${CONTAINER_NAME}..."
az container create \
  --name "${CONTAINER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --image "${IMAGE}" \
  --vnet "${VNET_NAME}" \
  --subnet "${SUBNET_NAME}" \
  --location "${LOCATION}" \
  --os-type Linux \
  --cpu 1 \
  --memory 1 \
  --environment-variables \
    SUBNET_NAME="${SUBNET_NAME}" \
    SUBNET_CIDR="${SUBNET_CIDR}" \
    VNET_NAME="${VNET_NAME}" \
    CONTAINER_NAME="${CONTAINER_NAME}" \
  --command-line "/bin/sh -c '${CUSTOM_SCRIPT}'" \
  --output none

log_info "Container instance created successfully"
log_info ""

# Get container details
CONTAINER_IP=$(az container show \
  --name "${CONTAINER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "ipAddress.ip" \
  --output tsv)

log_info "Container Details:"
log_info "  Name: ${CONTAINER_NAME}"
log_info "  Private IP: ${CONTAINER_IP}"
log_info "  Subnet: ${SUBNET_NAME} (${SUBNET_CIDR})"
log_info ""
log_info "To test from another container/VM:"
log_info "  curl http://${CONTAINER_IP}"
