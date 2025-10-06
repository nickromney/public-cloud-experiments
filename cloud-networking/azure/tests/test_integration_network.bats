#!/usr/bin/env bats
#
# Integration tests for Azure networking scripts
# Requires: Azure login, RESOURCE_GROUP set, resources created by 02-azure-simple-network.sh
#
# Run with: RESOURCE_GROUP=your-rg bats test_integration_network.bats

setup() {
  load setup_integration

  # Skip if not in integration mode
  if [[ "${BATS_INTEGRATION:-}" != "true" ]]; then
    skip "Integration tests require BATS_INTEGRATION=true"
  fi

  # Verify RESOURCE_GROUP is set
  if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    skip "Integration tests require RESOURCE_GROUP environment variable"
  fi
}

# VNET tests
@test "VNET vnet-simple exists in Azure" {
  run az network vnet show \
    --name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "vnet-simple"
}

@test "VNET has correct address space" {
  run az network vnet show \
    --name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "addressSpace.addressPrefixes[0]" \
    -o tsv

  assert_success
  assert_output "10.0.0.0/16"
}

# Subnet tests
@test "Subnet snet-subnet1 exists" {
  run az network vnet subnet show \
    --name snet-subnet1 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "snet-subnet1"
}

@test "Subnet snet-subnet1 has correct address prefix" {
  run az network vnet subnet show \
    --name snet-subnet1 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "addressPrefix" \
    -o tsv

  assert_success
  assert_output "10.0.10.0/24"
}

@test "Subnet snet-subnet2 exists" {
  run az network vnet subnet show \
    --name snet-subnet2 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "snet-subnet2"
}

@test "Subnet snet-subnet3 exists" {
  run az network vnet subnet show \
    --name snet-subnet3 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "snet-subnet3"
}

@test "Subnet snet-subnet4 exists" {
  run az network vnet subnet show \
    --name snet-subnet4 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "snet-subnet4"
}

# NSG tests
@test "NSG nsg-simple exists" {
  run az network nsg show \
    --name nsg-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "nsg-simple"
}

@test "Subnet snet-subnet1 is associated with NSG" {
  run az network vnet subnet show \
    --name snet-subnet1 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkSecurityGroup.id" \
    -o tsv

  assert_success
  # Should contain the NSG name in the resource ID
  assert_output --partial "nsg-simple"
}

# Location consistency tests
@test "VNET location matches resource group location" {
  RG_LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  VNET_LOCATION=$(az network vnet show --name vnet-simple --resource-group "${RESOURCE_GROUP}" --query location -o tsv)

  [[ "${VNET_LOCATION}" == "${RG_LOCATION}" ]]
}

@test "NSG location matches resource group location" {
  RG_LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
  NSG_LOCATION=$(az network nsg show --name nsg-simple --resource-group "${RESOURCE_GROUP}" --query location -o tsv)

  [[ "${NSG_LOCATION}" == "${RG_LOCATION}" ]]
}
