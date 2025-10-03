#!/usr/bin/env bash
# Create Azure Network Security Group with rules
set -euo pipefail

RESOURCE_GROUP="${1:?Resource group required}"
NSG_NAME="${2:?NSG name required}"
LOCATION="${3:-eastus2}"

# Create NSG
az network nsg create \
  --name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

# Allow HTTPS inbound from anywhere
az network nsg rule create \
  --name "AllowHTTPS" \
  --nsg-name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 443 \
  --output none

# Allow TCP between subnets (10.0.10.0/24 and 10.0.20.0/24)
az network nsg rule create \
  --name "AllowTCPBetweenSubnets" \
  --nsg-name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "10.0.10.0/24" "10.0.20.0/24" \
  --source-port-ranges "*" \
  --destination-address-prefixes "10.0.10.0/24" "10.0.20.0/24" \
  --destination-port-ranges "*" \
  --output none

# Allow ICMP between subnets
az network nsg rule create \
  --name "AllowICMPBetweenSubnets" \
  --nsg-name "${NSG_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --priority 120 \
  --direction Inbound \
  --access Allow \
  --protocol Icmp \
  --source-address-prefixes "10.0.10.0/24" "10.0.20.0/24" \
  --source-port-ranges "*" \
  --destination-address-prefixes "10.0.10.0/24" "10.0.20.0/24" \
  --destination-port-ranges "*" \
  --output none
