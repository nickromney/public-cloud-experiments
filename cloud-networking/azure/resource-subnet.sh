#!/usr/bin/env bash
# Create Azure Subnet
set -euo pipefail

RESOURCE_GROUP="${1:?Resource group required}"
VNET_NAME="${2:?VNET name required}"
SUBNET_NAME="${3:?Subnet name required}"
SUBNET_PREFIX="${4:?Subnet prefix required}"
NSG_NAME="${5:-}"
PRIVATE="${6:-false}"  # Private subnet (no default outbound access)
DELEGATION="${7:-}"    # Subnet delegation (e.g., Microsoft.ContainerInstance/containerGroups)

ARGS=(
  --name "${SUBNET_NAME}"
  --vnet-name "${VNET_NAME}"
  --resource-group "${RESOURCE_GROUP}"
  --address-prefix "${SUBNET_PREFIX}"
  --output none
)

# Add NSG if provided
if [[ -n "${NSG_NAME}" ]]; then
  ARGS+=(--network-security-group "${NSG_NAME}")
fi

# Add private subnet flag if true
if [[ "${PRIVATE}" == "true" ]]; then
  ARGS+=(--default-outbound false)
fi

# Add delegation if provided
if [[ -n "${DELEGATION}" ]]; then
  ARGS+=(--delegations "${DELEGATION}")
fi

az network vnet subnet create "${ARGS[@]}"
