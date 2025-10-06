#!/usr/bin/env bats
#
# Tests for error handling in Azure networking scripts
# Verifies proper error detection, messages, and exit codes

setup() {
  load setup
}

teardown() {
  load teardown
}

# Azure CLI not logged in errors
@test "02-azure-simple-network.sh fails when not logged in to Azure" {
  mock_az_not_logged_in

  run ./02-azure-simple-network.sh

  assert_failure
  assert_output --partial "Not logged in to Azure"
}

@test "03-azure-network-aci.sh fails when not logged in to Azure" {
  mock_az_not_logged_in

  run ./03-azure-network-aci.sh

  assert_failure
  assert_output --partial "Not logged in"
}

# Missing required parameters
@test "resource-vnet.sh exits with error when RESOURCE_GROUP missing" {
  run bash -c './resource-vnet.sh 2>&1' || true

  assert_failure
  assert_output --partial "Resource group required"
}

@test "resource-vnet.sh exits with error when VNET_NAME missing" {
  run bash -c './resource-vnet.sh rg-test 2>&1' || true

  assert_failure
  assert_output --partial "VNET name required"
}

@test "resource-subnet.sh exits with error when SUBNET_NAME missing" {
  run bash -c './resource-subnet.sh rg-test vnet-test 2>&1' || true

  assert_failure
  assert_output --partial "Subnet name required"
}

@test "resource-subnet.sh requires 4 parameters minimum" {
  # resource-subnet.sh requires: rg, vnet, subnet, prefix
  run bash -c './resource-subnet.sh rg-test vnet-test snet-test 2>&1' || true

  assert_failure
}

@test "resource-nsg.sh exits with error when NSG_NAME missing" {
  run bash -c './resource-nsg.sh rg-test 2>&1' || true

  assert_failure
  assert_output --partial "NSG name required"
}

# resource-container-instance.sh and resource-virtual-machine.sh use env vars with defaults
# They don't require parameters, so no error tests needed

# Environment variable requirements
@test "resource-nsg-rule.sh requires RULE_NAME environment variable" {
  run ./resource-nsg-rule.sh 2>&1 || true

  assert_failure
  assert_output --partial "Rule name required"
}

@test "resource-route-table.sh requires ROUTE_TABLE_NAME environment variable" {
  run ./resource-route-table.sh 2>&1 || true

  assert_failure
  assert_output --partial "Route table name required"
}

@test "resource-route.sh requires ROUTE_TABLE_NAME" {
  ROUTE_NAME=test \
  ADDRESS_PREFIX=0.0.0.0/0 \
  NEXT_HOP_TYPE=Internet \
    run ./resource-route.sh 2>&1 || true

  assert_failure
  assert_output --partial "Route table name required"
}

@test "resource-route.sh requires ROUTE_NAME" {
  ROUTE_TABLE_NAME=rt-test \
  ADDRESS_PREFIX=0.0.0.0/0 \
  NEXT_HOP_TYPE=Internet \
    run ./resource-route.sh 2>&1 || true

  assert_failure
  assert_output --partial "Route name required"
}

@test "resource-route.sh requires ADDRESS_PREFIX" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=test \
  NEXT_HOP_TYPE=Internet \
    run ./resource-route.sh 2>&1 || true

  assert_failure
  assert_output --partial "Address prefix required"
}

@test "resource-route.sh requires NEXT_HOP_TYPE" {
  ROUTE_TABLE_NAME=rt-test \
  ROUTE_NAME=test \
  ADDRESS_PREFIX=0.0.0.0/0 \
    run ./resource-route.sh 2>&1 || true

  assert_failure
  assert_output --partial "Next hop type required"
}

# Note: resource-route.sh validation logic for NEXT_HOP_IP could be improved
# This would be a good TDD candidate

# Azure resource not found errors - realistic error response
@test "Mock az returns exit code 3 for ResourceNotFound" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az group show --name nonexistent

  # Azure returns exit code 3 for ResourceNotFound
  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound error message" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network vnet show --name test --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "was not found"
}

@test "Mock az returns exit code 3 for container not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az container show --name test-container --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for container" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az container show --name test-container --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "Microsoft.ContainerInstance/containerGroups"
}

@test "Mock az returns exit code 3 for VM not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az vm show --name test-vm --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for VM" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az vm show --name test-vm --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "Microsoft.Compute/virtualMachines"
}

@test "Mock az returns exit code 3 for NSG not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network nsg show --name test-nsg --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for NSG" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network nsg show --name test-nsg --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "Microsoft.Network/networkSecurityGroups"
}

@test "Mock az returns exit code 3 for subnet not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network vnet subnet show --name test-subnet --vnet-name test-vnet --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for subnet" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network vnet subnet show --name test-subnet --vnet-name test-vnet --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "subnets/test-subnet"
}

@test "Mock az returns exit code 3 for route table not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network route-table show --name test-rt --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for route table" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network route-table show --name test-rt --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "Microsoft.Network/routeTables"
}

@test "Mock az returns exit code 3 for public IP not found" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network public-ip show --name test-ip --resource-group test

  [ "$status" -eq 3 ]
}

@test "Mock az returns ResourceNotFound for public IP" {
  export AZ_MOCK_RESOURCE_NOT_FOUND=true

  run az network public-ip show --name test-ip --resource-group test 2>&1

  assert_failure
  assert_output --partial "ResourceNotFound"
  assert_output --partial "Microsoft.Network/publicIPAddresses"
}

# Invalid parameter values
@test "resource-nsg-rule.sh validates ACTION is create or delete" {
  RULE_NAME=TestRule \
  PRIORITY=100 \
  DIRECTION=Inbound \
  ACCESS=Allow \
  PROTOCOL=Tcp \
  DEST_PORT=80 \
  ACTION=invalid \
    run ./resource-nsg-rule.sh 2>&1 || true

  # Should only accept 'create' or 'delete'
  assert_failure
}

# Error propagation with set -e
@test "Scripts exit on first error due to set -e" {
  # All scripts should have set -e, so first command failure stops execution

  # Test that resource-vnet.sh has set -e
  run grep "^set -e" resource-vnet.sh
  assert_success

  # Test that resource-subnet.sh has set -e
  run grep "^set -e" resource-subnet.sh
  assert_success
}

@test "Scripts use set -u to catch undefined variables" {
  # Scripts should have set -u to error on undefined variables

  run grep "set -.*u" resource-vnet.sh
  assert_success

  run grep "set -.*u" resource-subnet.sh
  assert_success
}

# Logging functions are defined in each script, not in common.sh (which doesn't exist)
# No need to test them separately

# Azure CLI command failures
@test "Scripts handle az command failures properly" {
  # Mock az to fail
  function az() {
    echo "ERROR: Command failed" >&2
    return 1
  }
  export -f az

  run bash -c './resource-vnet.sh rg-test vnet-test 2>&1' || true

  assert_failure
}

# Note: Scripts use `set -e` for error handling, which is good enough for these simple scripts
# More complex error handling (like trap cleanup) could be added later via TDD

# Readonly variable enforcement
@test "Scripts protect critical variables with readonly" {
  # Check that important configuration variables are readonly in orchestrators
  run bash -c 'source 02-azure-simple-network.sh 2>/dev/null; readonly RESOURCE_GROUP=test 2>&1' || true

  assert_failure
  assert_output --partial "readonly"
}

# Edge cases
@test "resource-subnet.sh handles empty NSG parameter correctly" {
  # Empty string should not add NSG flag
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24 ""

  assert_success
  # Verify NSG flag not present
  local has_nsg=false
  for arg in "${AZ_ARGS_CALLED[@]}"; do
    if [[ "$arg" == "--network-security-group" ]]; then
      has_nsg=true
    fi
  done
  [[ "$has_nsg" == "false" ]]
}

@test "resource-subnet.sh handles false private flag correctly" {
  # "false" should not add --default-outbound false
  run ./resource-subnet.sh rg-test vnet-test snet-test 10.0.1.0/24 "" "false"

  assert_success
  # Should not have --default-outbound flag
  local has_outbound=false
  for arg in "${AZ_ARGS_CALLED[@]}"; do
    if [[ "$arg" == "--default-outbound" ]]; then
      has_outbound=true
    fi
  done
  [[ "$has_outbound" == "false" ]]
}

# Cleanup and error recovery
# Note: These simple scripts don't use trap cleanup yet
# Could be added later if needed
