#!/usr/bin/env bash
#
# Create Azure Route Table
# Used for User Defined Routes (UDR)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly LOCATION="${LOCATION:-eastus2}"
readonly ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:?Route table name required}"
readonly DISABLE_BGP_PROPAGATION="${DISABLE_BGP_PROPAGATION:-false}"

az network route-table create \
  --name "${ROUTE_TABLE_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --disable-bgp-route-propagation "${DISABLE_BGP_PROPAGATION}" \
  --output none
