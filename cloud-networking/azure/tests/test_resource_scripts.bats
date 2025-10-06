#!/usr/bin/env bats
#
# Tests for resource-*.sh scripts
# Tests that scripts construct correct Azure CLI commands (using mocks)

setup() {
  load setup
}

teardown() {
  load teardown
}

# resource-vnet.sh tests
@test "resource-vnet.sh constructs correct vnet create command" {
  run ./resource-vnet.sh rg-test vnet-test 10.0.0.0/16 eastus2

  assert_success
  assert_az_called "network vnet create"
  assert_az_arg "--name" "vnet-test"
  assert_az_arg "--resource-group" "rg-test"
  assert_az_arg "--address-prefixes" "10.0.0.0/16"
  assert_az_arg "--location" "eastus2"
}

@test "resource-vnet.sh uses default VNET_PREFIX" {
  run ./resource-vnet.sh rg-test vnet-test

  assert_success
  assert_az_arg "--address-prefixes" "10.0.0.0/16"
}

@test "resource-vnet.sh uses default LOCATION" {
  run ./resource-vnet.sh rg-test vnet-test

  assert_success
  assert_az_arg "--location" "eastus2"
}

# resource-subnet.sh tests
@test "resource-subnet.sh constructs correct subnet create command" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.10.0/24

  assert_success
  assert_az_called "network vnet subnet create"
  assert_az_arg "--name" "snet-test"
  assert_az_arg "--vnet-name" "vnet-test"
  assert_az_arg "--resource-group" "rg-test"
  assert_az_arg "--address-prefix" "10.0.10.0/24"
}

@test "resource-subnet.sh adds NSG when provided" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.10.0/24 nsg-test

  assert_success
  assert_az_arg "--network-security-group" "nsg-test"
}

@test "resource-subnet.sh adds private flag when true" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.10.0/24 "" "true"

  assert_success
  assert_az_arg "--default-outbound" "false"
}

@test "resource-subnet.sh adds delegation when provided" {
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.10.0/24 "" "false" "Microsoft.ContainerInstance/containerGroups"

  assert_success
  assert_az_arg "--delegations" "Microsoft.ContainerInstance/containerGroups"
}

# resource-nsg.sh tests
@test "resource-nsg.sh constructs correct nsg create command" {
  run ./resource-nsg.sh rg-test nsg-test eastus2

  assert_success
  assert_az_called "network nsg create"
  assert_az_arg "--name" "nsg-test"
  assert_az_arg "--resource-group" "rg-test"
  assert_az_arg "--location" "eastus2"
}

# resource-nsg-rule.sh tests
@test "resource-nsg-rule.sh creates rule with correct parameters" {
  RULE_NAME=TestRule \
  PRIORITY=100 \
  DIRECTION=Inbound \
  ACCESS=Allow \
  PROTOCOL=Tcp \
  DEST_PORT=80 \
  ACTION=create \
  NSG_NAME=nsg-simple \
  RESOURCE_GROUP=rg-simple-vnet \
    run ./resource-nsg-rule.sh

  assert_success
  assert_az_called "network nsg rule create"
  assert_az_arg "--name" "TestRule"
  assert_az_arg "--priority" "100"
}

@test "resource-nsg-rule.sh fails without RULE_NAME" {
  run bash -c './resource-nsg-rule.sh 2>&1' || true

  assert_output --partial "RULE_NAME"
}

# resource-route-table.sh tests
@test "resource-route-table.sh constructs correct command" {
  ROUTE_TABLE_NAME=rt-test \
  RESOURCE_GROUP=rg-simple-vnet \
  LOCATION=eastus2 \
    run ./resource-route-table.sh

  assert_success
  assert_az_called "network route-table create"
  assert_az_arg "--name" "rt-test"
}

@test "resource-route-table.sh fails without ROUTE_TABLE_NAME" {
  run bash -c './resource-route-table.sh 2>&1' || true

  assert_output --partial "Route table name required"
}

# resource-route.sh tests
@test "resource-route.sh constructs correct route create command" {
  RESOURCE_GROUP=rg-simple-vnet \
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=default-route \
  ADDRESS_PREFIX=0.0.0.0/0 \
  NEXT_HOP_TYPE=VirtualAppliance \
  NEXT_HOP_IP=10.0.30.4 \
    run ./resource-route.sh

  assert_success
  assert_az_called "network route-table route create"
  assert_az_arg "--route-table-name" "rt-test"
  assert_az_arg "--address-prefix" "0.0.0.0/0"
  assert_az_arg "--next-hop-type" "VirtualAppliance"
  assert_az_arg "--next-hop-ip-address" "10.0.30.4"
}

@test "resource-route.sh fails without required parameters" {
  run bash -c './resource-route.sh 2>&1' || true

  assert_output --partial "required"
}
