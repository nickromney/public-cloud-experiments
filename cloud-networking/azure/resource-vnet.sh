#!/usr/bin/env bash
# Create Azure Virtual Network
set -euo pipefail

RESOURCE_GROUP="${1:?Resource group required}"
VNET_NAME="${2:?VNET name required}"
VNET_PREFIX="${3:-10.0.0.0/16}"
LOCATION="${4:-eastus2}"

az network vnet create \
  --name "${VNET_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --address-prefixes "${VNET_PREFIX}" \
  --output none
