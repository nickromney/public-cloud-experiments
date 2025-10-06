#!/usr/bin/env bash
#
# Manage NSG rules - create, update, or delete individual rules
# Usage: ACTION=create|delete ./resource-nsg-rule.sh

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly NSG_NAME="${NSG_NAME:-nsg-simple}"
readonly RULE_NAME="${RULE_NAME:?Rule name required}"
readonly ACTION="${ACTION:-create}"  # create or delete

# Rule parameters (only needed for create)
readonly PRIORITY="${PRIORITY:-100}"
readonly DIRECTION="${DIRECTION:-Inbound}"
readonly ACCESS="${ACCESS:-Allow}"
readonly PROTOCOL="${PROTOCOL:-Tcp}"
readonly SOURCE_PREFIX="${SOURCE_PREFIX:-*}"
readonly SOURCE_PORT="${SOURCE_PORT:-*}"
readonly DEST_PREFIX="${DEST_PREFIX:-*}"
readonly DEST_PORT="${DEST_PORT:-*}"

if [[ "${ACTION}" == "create" ]]; then
  az network nsg rule create \
    --name "${RULE_NAME}" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --priority "${PRIORITY}" \
    --direction "${DIRECTION}" \
    --access "${ACCESS}" \
    --protocol "${PROTOCOL}" \
    --source-address-prefixes "${SOURCE_PREFIX}" \
    --source-port-ranges "${SOURCE_PORT}" \
    --destination-address-prefixes "${DEST_PREFIX}" \
    --destination-port-ranges "${DEST_PORT}" \
    --output none
elif [[ "${ACTION}" == "delete" ]]; then
  az network nsg rule delete \
    --name "${RULE_NAME}" \
    --nsg-name "${NSG_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output none
else
  echo "ERROR: ACTION must be 'create' or 'delete'" >&2
  exit 1
fi
