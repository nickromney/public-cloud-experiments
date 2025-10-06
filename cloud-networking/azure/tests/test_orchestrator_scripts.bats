#!/usr/bin/env bats
#
# Tests for orchestrator scripts (numbered scripts that call resource scripts)
# Tests environment variable handling and script composition

setup() {
  load setup
}

teardown() {
  load teardown
}

# 02-azure-simple-network.sh tests
@test "02-azure-simple-network.sh uses RESOURCE_GROUP env var" {
  # Source script to check variables (don't execute)
  RESOURCE_GROUP=custom-rg
  run bash -c 'RESOURCE_GROUP=custom-rg; source 02-azure-simple-network.sh 2>/dev/null; echo "$RESOURCE_GROUP"' || true

  assert_output --partial "custom-rg"
}

@test "02-azure-simple-network.sh uses default RESOURCE_GROUP" {
  run bash -c 'source 02-azure-simple-network.sh 2>/dev/null; echo "$RESOURCE_GROUP"' || true

  assert_output --partial "rg-simple-vnet"
}

@test "02-azure-simple-network.sh checks Azure CLI login" {
  mock_az_not_logged_in

  run ./02-azure-simple-network.sh

  assert_failure
  assert_output --partial "Not logged in to Azure"
}

@test "02-azure-simple-network.sh calculates SCRIPT_DIR" {
  run bash -c 'source 02-azure-simple-network.sh 2>/dev/null; test -n "$SCRIPT_DIR"' || true

  assert_success
}

# 03-azure-network-aci.sh tests
@test "03-azure-network-aci.sh uses VNET_NAME env var" {
  run bash -c 'VNET_NAME=custom-vnet; source 03-azure-network-aci.sh 2>/dev/null; echo "$VNET_NAME"' || true

  assert_output --partial "custom-vnet"
}

@test "03-azure-network-aci.sh sets DELEGATION constant" {
  run bash -c 'source 03-azure-network-aci.sh 2>/dev/null; echo "$DELEGATION"' || true

  assert_output --partial "Microsoft.ContainerInstance/containerGroups"
}

# 07-vm.sh tests
@test "07-vm.sh uses CUSTOM_DATA env var" {
  # Check that script references CUSTOM_DATA variable
  run grep -q "CUSTOM_DATA" 07-vm.sh

  assert_success
}

# 09-custom-containers.sh tests
@test "09-custom-containers.sh sets container environment correctly" {
  # Verify it would call resource script with correct env
  run grep -A 2 "SUBNET_NAME=snet-subnet1" 09-custom-containers.sh

  assert_success
  assert_output --partial "CONTAINER_NAME=aci-custom-subnet1"
}

# 12-private-vm.sh tests
@test "12-private-vm.sh deploys to subnet4" {
  run grep "SUBNET_NAME=snet-subnet4" 12-private-vm.sh

  assert_success
}

@test "12-private-vm.sh sets VM_NAME to vm-private" {
  run grep "VM_NAME=vm-private" 12-private-vm.sh

  assert_success
}

# 14-nva-routing.sh tests
@test "14-nva-routing.sh uses NVA_VM env var" {
  run bash -c 'source 14-nva-routing.sh 2>/dev/null; echo "$NVA_VM"' || true

  assert_output --partial "vm-firewall"
}

@test "14-nva-routing.sh has route table name variable" {
  run bash -c 'source 14-nva-routing.sh 2>/dev/null; echo "$ROUTE_TABLE_NAME"' || true

  assert_output --partial "rt-subnet4-via-nva"
}

# General orchestrator patterns
@test "Orchestrator scripts use log_info function" {
  run grep -l "log_info" 02-azure-simple-network.sh 03-azure-network-aci.sh

  assert_success
}

@test "Orchestrator scripts use log_error function" {
  run grep -l "log_error" 02-azure-simple-network.sh 03-azure-network-aci.sh

  assert_success
}

@test "Orchestrator scripts check for Azure CLI" {
  run grep -l "az account show" 02-azure-simple-network.sh

  assert_success
}
