#!/usr/bin/env bats
#
# Tests for detailed Azure CLI command construction
# Verifies exact command syntax, queries, output formats, and argument handling

setup() {
  load setup
}

teardown() {
  load teardown
}

# Output format tests
@test "resource-vnet.sh uses --output none for create commands" {
  run ./resource-vnet.sh rg-test vnet-test

  assert_success
  assert_az_arg "--output" "none"
}

@test "resource-subnet.sh uses --output none for create commands" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24

  assert_success
  assert_az_arg "--output" "none"
}

@test "resource-nsg.sh uses --output none for create commands" {
  run ./resource-nsg.sh rg-test nsg-test eastus2

  assert_success
  assert_az_arg "--output" "none"
}

# Query parameter tests
@test "06-container-tests.sh uses correct query for IP address" {
  # Check script contains proper query syntax
  run grep -o "\-\-query.*ipAddress\.ip" 06-container-tests.sh

  assert_success
  assert_output --partial "ipAddress.ip"
}

@test "14-nva-routing.sh uses correct query for private IP" {
  # Check script contains proper query for VM private IP
  run grep -o "\-\-query.*privateIps" 14-nva-routing.sh

  assert_success
  assert_output --partial "privateIps"
}

# Conditional argument tests
@test "resource-subnet.sh omits NSG when not provided" {
  mock_az_setup
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24

  assert_success
  # Should not have NSG argument if none provided
  local has_nsg=false
  for arg in "${AZ_ARGS_CALLED[@]}"; do
    if [[ "$arg" == "--network-security-group" ]]; then
      has_nsg=true
    fi
  done
  [[ "$has_nsg" == "false" ]]
}

@test "resource-subnet.sh includes NSG when provided" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24 nsg-test

  assert_success
  assert_az_arg "--network-security-group" "nsg-test"
}

@test "resource-subnet.sh handles private subnet flag correctly" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24 "" "true"

  assert_success
  assert_az_arg "--default-outbound" "false"
}

@test "resource-subnet.sh handles delegation correctly" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24 "" "false" "Microsoft.ContainerInstance/containerGroups"

  assert_success
  assert_az_arg "--delegations" "Microsoft.ContainerInstance/containerGroups"
}

# Route table command construction
@test "resource-route.sh constructs VirtualAppliance route correctly" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=default-route \
  ADDRESS_PREFIX=0.0.0.0/0 \
  NEXT_HOP_TYPE=VirtualAppliance \
  NEXT_HOP_IP=10.0.30.4 \
    run ./resource-route.sh

  assert_success
  assert_az_called "network route-table route create"
  assert_az_arg "--next-hop-type" "VirtualAppliance"
  assert_az_arg "--next-hop-ip-address" "10.0.30.4"
}

@test "resource-route.sh constructs Internet route correctly" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=internet-route \
  ADDRESS_PREFIX=8.8.8.8/32 \
  NEXT_HOP_TYPE=Internet \
    run ./resource-route.sh

  assert_success
  assert_az_arg "--next-hop-type" "Internet"
}

@test "resource-route.sh constructs VnetLocal route correctly" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=local-route \
  ADDRESS_PREFIX=10.0.0.0/16 \
  NEXT_HOP_TYPE=VnetLocal \
    run ./resource-route.sh

  assert_success
  assert_az_arg "--next-hop-type" "VnetLocal"
}

# NSG rule command construction
@test "resource-nsg-rule.sh constructs Inbound Allow rule correctly" {
  RULE_NAME=AllowHTTP \
  PRIORITY=100 \
  DIRECTION=Inbound \
  ACCESS=Allow \
  PROTOCOL=Tcp \
  DEST_PORT=80 \
  ACTION=create \
    run ./resource-nsg-rule.sh

  assert_success
  assert_az_called "network nsg rule create"
  assert_az_arg "--direction" "Inbound"
  assert_az_arg "--access" "Allow"
  assert_az_arg "--protocol" "Tcp"
  assert_az_arg "--destination-port-range" "80"
}

@test "resource-nsg-rule.sh constructs Outbound Deny rule correctly" {
  RULE_NAME=DenyInternet \
  PRIORITY=200 \
  DIRECTION=Outbound \
  ACCESS=Deny \
  PROTOCOL=* \
  DEST_PORT=* \
  DEST_PREFIX=Internet \
  ACTION=create \
    run ./resource-nsg-rule.sh

  assert_success
  assert_az_arg "--direction" "Outbound"
  assert_az_arg "--access" "Deny"
  assert_az_arg "--protocol" "*"
  assert_az_arg "--destination-address-prefixes" "Internet"
}

@test "resource-nsg-rule.sh handles delete action correctly" {
  RULE_NAME=TestRule \
  ACTION=delete \
    run ./resource-nsg-rule.sh

  assert_success
  assert_az_called "network nsg rule delete"
  assert_az_arg "--name" "TestRule"
}

# Container instance command construction
@test "resource-container-instance.sh contains container create command" {
  run grep -q "az container create" resource-container-instance.sh

  assert_success
}

@test "resource-container-instance.sh uses VNET and SUBNET variables" {
  run grep -E "(--vnet|--subnet)" resource-container-instance.sh

  assert_success
}

# Virtual machine command construction
@test "resource-virtual-machine.sh contains vm create command" {
  run grep -q "az vm create" resource-virtual-machine.sh

  assert_success
}

@test "resource-virtual-machine.sh uses VM_SIZE variable" {
  run grep -q "VM_SIZE" resource-virtual-machine.sh

  assert_success
}

# Parameter validation tests
@test "resource-vnet.sh validates RESOURCE_GROUP parameter" {
  run bash -c './resource-vnet.sh 2>&1' || true
  assert_output --partial "Resource group required"
}

@test "resource-vnet.sh validates VNET_NAME parameter" {
  run bash -c './resource-vnet.sh rg-test 2>&1' || true
  assert_output --partial "VNET name required"
}

@test "resource-subnet.sh validates all required parameters" {
  run bash -c './resource-subnet.sh 2>&1' || true
  assert_output --partial "required"
}

@test "resource-route.sh validates ROUTE_TABLE_NAME" {
  ROUTE_NAME=test \
  ADDRESS_PREFIX=0.0.0.0/0 \
  NEXT_HOP_TYPE=Internet \
    run ./resource-route.sh 2>&1 || true

  assert_output --partial "Route table name required"
}

@test "resource-route.sh validates NEXT_HOP_TYPE" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=test \
  ADDRESS_PREFIX=0.0.0.0/0 \
    run ./resource-route.sh 2>&1 || true

  assert_output --partial "Next hop type required"
}

# Default value tests
@test "resource-vnet.sh uses default location when not specified" {
  run ./resource-vnet.sh rg-test vnet-test

  assert_success
  assert_az_arg "--location" "eastus2"
}

@test "resource-vnet.sh uses default address prefix when not specified" {
  run ./resource-vnet.sh rg-test vnet-test

  assert_success
  assert_az_arg "--address-prefixes" "10.0.0.0/16"
}

@test "resource-container-instance.sh has default IMAGE" {
  run grep "IMAGE.*mcr.microsoft.com/oss/nginx/nginx" resource-container-instance.sh

  assert_success
}

@test "resource-virtual-machine.sh has default VM_SIZE" {
  run grep "VM_SIZE.*Standard_B2s" resource-virtual-machine.sh

  assert_success
}
