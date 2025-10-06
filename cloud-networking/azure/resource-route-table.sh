#!/usr/bin/env bash
#
# Create Azure Route Table
# Used for User Defined Routes (UDR)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:?Route table name required}"
readonly DISABLE_BGP_PROPAGATION="${DISABLE_BGP_PROPAGATION:-false}"

# Detect location from resource group if LOCATION not set
if [[ -z "${LOCATION:-}" ]]; then
  LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv 2>/dev/null || echo "")
  if [[ -z "${LOCATION}" ]]; then
    echo "ERROR: Could not detect location from resource group ${RESOURCE_GROUP}" >&2
    exit 1
  fi
fi
readonly LOCATION

az network route-table create \
  --name "${ROUTE_TABLE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --disable-bgp-route-propagation "${DISABLE_BGP_PROPAGATION}" \
  --output none
