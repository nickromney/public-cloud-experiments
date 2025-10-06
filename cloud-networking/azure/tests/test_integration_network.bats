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

@test "Subnet snet-subnet4 has defaultOutboundAccess false" {
  run az network vnet subnet show \
    --name snet-subnet4 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "defaultOutboundAccess" \
    -o tsv

  assert_success
  assert_output "false"
}

@test "Subnet snet-subnet5 exists" {
  run az network vnet subnet show \
    --name snet-subnet5 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "snet-subnet5"
}

@test "Subnet snet-subnet5 has correct address prefix" {
  run az network vnet subnet show \
    --name snet-subnet5 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "addressPrefix" \
    -o tsv

  assert_success
  assert_output "10.0.50.0/24"
}

@test "Subnet snet-subnet5 has defaultOutboundAccess true" {
  run az network vnet subnet show \
    --name snet-subnet5 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "defaultOutboundAccess" \
    -o tsv

  assert_success
  assert_output "true"
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

# VM tests
@test "VM vm-test3 exists" {
  run az vm show \
    --name vm-test3 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "vm-test3"
}

@test "VM vm-test3 is in subnet3" {
  run az vm show \
    --name vm-test3 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkProfile.networkInterfaces[0].id" \
    -o tsv

  assert_success

  # Get NIC name from the resource ID
  NIC_ID="${output}"
  NIC_SUBNET=$(az network nic show --ids "${NIC_ID}" --query "ipConfigurations[0].subnet.id" -o tsv)

  # Should contain snet-subnet3
  [[ "${NIC_SUBNET}" == *"snet-subnet3"* ]]
}

@test "VM vm-test3 NIC has IP forwarding enabled" {
  run az vm show \
    --name vm-test3 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkProfile.networkInterfaces[0].id" \
    -o tsv

  assert_success

  NIC_ID="${output}"
  IP_FORWARDING=$(az network nic show --ids "${NIC_ID}" --query "enableIPForwarding" -o tsv)

  [[ "${IP_FORWARDING}" == "true" ]]
}

@test "VM vm-test4 exists" {
  run az vm show \
    --name vm-test4 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "vm-test4"
}

@test "VM vm-test4 is in subnet4" {
  run az vm show \
    --name vm-test4 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkProfile.networkInterfaces[0].id" \
    -o tsv

  assert_success

  NIC_ID="${output}"
  NIC_SUBNET=$(az network nic show --ids "${NIC_ID}" --query "ipConfigurations[0].subnet.id" -o tsv)

  [[ "${NIC_SUBNET}" == *"snet-subnet4"* ]]
}

@test "VM vm-test5 exists" {
  run az vm show \
    --name vm-test5 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "vm-test5"
}

@test "VM vm-test5 is in subnet5" {
  run az vm show \
    --name vm-test5 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkProfile.networkInterfaces[0].id" \
    -o tsv

  assert_success

  NIC_ID="${output}"
  NIC_SUBNET=$(az network nic show --ids "${NIC_ID}" --query "ipConfigurations[0].subnet.id" -o tsv)

  [[ "${NIC_SUBNET}" == *"snet-subnet5"* ]]
}

# Public IP tests
@test "Public IP vm-test3-pip exists" {
  run az network public-ip show \
    --name vm-test3-pip \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "vm-test3-pip"
}

@test "Public IP vm-test3-pip is attached to vm-test3 NIC" {
  run az vm show \
    --name vm-test3 \
    --resource-group "${RESOURCE_GROUP}" \
    --query "networkProfile.networkInterfaces[0].id" \
    -o tsv

  assert_success

  NIC_ID="${output}"
  PUBLIC_IP=$(az network nic show --ids "${NIC_ID}" --query "ipConfigurations[0].publicIPAddress.id" -o tsv)

  [[ "${PUBLIC_IP}" == *"vm-test3-pip"* ]]
}

@test "Public IP vm-test3-pip has an IP address allocated" {
  run az network public-ip show \
    --name vm-test3-pip \
    --resource-group "${RESOURCE_GROUP}" \
    --query "ipAddress" \
    -o tsv

  assert_success
  # Should have an IP address (not empty)
  [[ -n "${output}" ]]
}

# Route table tests
@test "Route table rt-subnet4-via-nva exists" {
  run az network route-table show \
    --name rt-subnet4-via-nva \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "rt-subnet4-via-nva"
}

@test "Route table rt-subnet4-via-nva is associated with subnet4" {
  run az network vnet subnet show \
    --name snet-subnet4 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "routeTable.id" \
    -o tsv

  assert_success
  [[ "${output}" == *"rt-subnet4-via-nva"* ]]
}

@test "Route table rt-subnet4-via-nva has default route to NVA" {
  run az network route-table route show \
    --name default-via-nva \
    --route-table-name rt-subnet4-via-nva \
    --resource-group "${RESOURCE_GROUP}" \
    --query "addressPrefix" \
    -o tsv

  assert_success
  assert_output "0.0.0.0/0"
}

@test "Route table rt-subnet4-via-nva default route points to 10.0.30.4" {
  run az network route-table route show \
    --name default-via-nva \
    --route-table-name rt-subnet4-via-nva \
    --resource-group "${RESOURCE_GROUP}" \
    --query "nextHopIpAddress" \
    -o tsv

  assert_success
  assert_output "10.0.30.4"
}

@test "Route table rt-subnet5-via-nva exists" {
  run az network route-table show \
    --name rt-subnet5-via-nva \
    --resource-group "${RESOURCE_GROUP}" \
    --query "name" \
    -o tsv

  assert_success
  assert_output "rt-subnet5-via-nva"
}

@test "Route table rt-subnet5-via-nva is associated with subnet5" {
  run az network vnet subnet show \
    --name snet-subnet5 \
    --vnet-name vnet-simple \
    --resource-group "${RESOURCE_GROUP}" \
    --query "routeTable.id" \
    -o tsv

  assert_success
  [[ "${output}" == *"rt-subnet5-via-nva"* ]]
}

# Connectivity tests
@test "VM vm-test4 can reach vm-test3 (intra-VNet connectivity)" {
  run az vm run-command invoke \
    --name vm-test4 \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "ping -c 2 -W 5 10.0.30.4" \
    --query "value[0].message" \
    -o tsv

  assert_success
  assert_output --partial "2 packets transmitted, 2 received"
}

@test "VM vm-test5 can reach vm-test3 (intra-VNet connectivity)" {
  run az vm run-command invoke \
    --name vm-test5 \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "ping -c 2 -W 5 10.0.30.4" \
    --query "value[0].message" \
    -o tsv

  assert_success
  assert_output --partial "2 packets transmitted, 2 received"
}

@test "VM vm-test3 can access internet (has public IP)" {
  run az vm run-command invoke \
    --name vm-test3 \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "curl -s -m 10 http://ifconfig.me" \
    --query "value[0].message" \
    -o tsv

  assert_success
  # Should return an IP address (not empty)
  [[ -n "${output}" ]]
}

@test "VM vm-test4 CANNOT access internet (private subnet, no explicit outbound)" {
  run az vm run-command invoke \
    --name vm-test4 \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "timeout 10 curl -s -m 5 http://ifconfig.me || echo FAILED" \
    --query "value[0].message" \
    -o tsv

  assert_success
  assert_output --partial "FAILED"
}

@test "VM vm-test5 CANNOT access internet via NVA (default SNAT incompatible)" {
  run az vm run-command invoke \
    --name vm-test5 \
    --resource-group "${RESOURCE_GROUP}" \
    --command-id RunShellScript \
    --scripts "timeout 10 curl -s -m 5 http://ifconfig.me || echo FAILED" \
    --query "value[0].message" \
    -o tsv

  assert_success
  assert_output --partial "FAILED"
}
