#!/usr/bin/env bash
#
# Add route to route table
# Used for User Defined Routes (UDR)

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:?Route table name required}"
readonly ROUTE_NAME="${ROUTE_NAME:?Route name required}"
readonly ADDRESS_PREFIX="${ADDRESS_PREFIX:?Address prefix required (e.g., 0.0.0.0/0)}"
readonly NEXT_HOP_TYPE="${NEXT_HOP_TYPE:?Next hop type required (VirtualAppliance|VnetLocal|Internet|None)}"
readonly NEXT_HOP_IP="${NEXT_HOP_IP:-}"  # Required only if NEXT_HOP_TYPE=VirtualAppliance

ARGS=(
  --name "${ROUTE_NAME}"
  --route-table-name "${ROUTE_TABLE_NAME}"
  --resource-group "${RESOURCE_GROUP}"
  --address-prefix "${ADDRESS_PREFIX}"
  --next-hop-type "${NEXT_HOP_TYPE}"
  --output none
)

# Add next hop IP if specified
if [[ -n "${NEXT_HOP_IP}" ]]; then
  ARGS+=(--next-hop-ip-address "${NEXT_HOP_IP}")
fi

az network route-table route create "${ARGS[@]}"
