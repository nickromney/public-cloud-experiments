#!/usr/bin/env bats
#
# Validation tests for Azure networking scripts
# Tests script quality: executability, shebang, error handling

setup() {
  load setup
}

teardown() {
  load teardown
}

# Test all resource scripts are executable
@test "resource-vnet.sh is executable" {
  assert_executable "resource-vnet.sh"
}

@test "resource-subnet.sh is executable" {
  assert_executable "resource-subnet.sh"
}

@test "resource-nsg.sh is executable" {
  assert_executable "resource-nsg.sh"
}

@test "resource-container-instance.sh is executable" {
  assert_executable "resource-container-instance.sh"
}

@test "resource-virtual-machine.sh is executable" {
  assert_executable "resource-virtual-machine.sh"
}

# Test scripts have proper shebang
@test "resource-vnet.sh has shebang" {
  assert_has_shebang "resource-vnet.sh"
}

@test "02-azure-simple-network.sh has shebang" {
  assert_has_shebang "02-azure-simple-network.sh"
}

# Test scripts use set -euo pipefail
@test "resource-vnet.sh has set -euo pipefail" {
  assert_has_set_errexit "resource-vnet.sh"
}

@test "resource-subnet.sh has set -euo pipefail" {
  assert_has_set_errexit "resource-subnet.sh"
}

@test "02-azure-simple-network.sh has set -euo pipefail" {
  assert_has_set_errexit "02-azure-simple-network.sh"
}

# Test resource scripts validate required parameters
@test "resource-vnet.sh requires RESOURCE_GROUP parameter" {
  run bash -c './resource-vnet.sh 2>&1' || true
  assert_output --partial "Resource group required"
}

@test "resource-vnet.sh requires VNET_NAME parameter" {
  run bash -c './resource-vnet.sh rg-test 2>&1' || true
  assert_output --partial "VNET name required"
}

@test "resource-subnet.sh requires SUBNET_NAME parameter" {
  run bash -c './resource-subnet.sh rg-test vnet-test 2>&1' || true
  assert_output --partial "Subnet name required"
}

@test "resource-nsg.sh requires NSG_NAME parameter" {
  run bash -c './resource-nsg.sh rg-test 2>&1' || true
  assert_output --partial "NSG name required"
}

# Test scripts use readonly for constants in orchestrators
@test "02-azure-simple-network.sh uses readonly for configuration" {
  assert_file_contains "02-azure-simple-network.sh" "readonly RESOURCE_GROUP"
}

@test "03-azure-network-aci.sh uses readonly for configuration" {
  assert_file_contains "03-azure-network-aci.sh" "readonly VNET_NAME"
}

# Test scripts have proper comments
@test "resource-vnet.sh has description comment" {
  run head -n 3 resource-vnet.sh
  assert_output --partial "Create Azure Virtual Network"
}

@test "resource-subnet.sh has description comment" {
  run head -n 3 resource-subnet.sh
  assert_output --partial "Create Azure Subnet"
}

# Test scripts use --output none for az commands (reduce noise)
@test "resource-vnet.sh uses --output none" {
  assert_file_contains "resource-vnet.sh" "--output none"
}

@test "resource-subnet.sh uses --output none" {
  assert_file_contains "resource-subnet.sh" "--output none"
}
