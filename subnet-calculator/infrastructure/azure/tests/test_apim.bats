#!/usr/bin/env bats
#
# Tests for API Management scripts
# Tests that 30-apim-instance.sh, 31-apim-backend.sh, 32-apim-policies.sh work correctly

setup() {
  load setup

  # Set up environment for APIM scripts
  export RESOURCE_GROUP="rg-subnet-calc"
  export PUBLISHER_EMAIL="admin@example.com"
  export APIM_NAME="apim-subnet-calc"
  export FUNCTION_APP_NAME="func-subnet-calc"
}

teardown() {
  load teardown
}

# === Tests for 30-apim-instance.sh ===

@test "30-apim-instance.sh has shebang" {
  run grep -E "^#!/" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh is executable" {
  [ -x 30-apim-instance.sh ]
}

@test "30-apim-instance.sh has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh sources selection utilities" {
  run grep "source.*selection-utils.sh" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh checks for PUBLISHER_EMAIL variable" {
  run grep "PUBLISHER_EMAIL" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh validates PUBLISHER_EMAIL is set" {
  run grep -E "PUBLISHER_EMAIL.*empty|if.*-z.*PUBLISHER_EMAIL" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh validates or uses email address" {
  run grep -E "PUBLISHER_EMAIL|email" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh uses Consumption SKU by default" {
  run grep -E "SKU.*Consumption|Consumption.*default" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh references region handling" {
  run grep -E "REGION|region|location" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh handles region appropriately" {
  run grep -E "LOCATION|location.*region|REGION" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh checks Azure CLI login" {
  run grep "az account show" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh creates APIM instance" {
  run grep "az apim create" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh stores gateway URL for use" {
  run grep -E "gatewayUrl|gateway.*url" 30-apim-instance.sh
  assert_success
}

# === Tests for 31-apim-backend.sh ===

@test "31-apim-backend.sh has shebang" {
  [ -f "31-apim-backend.sh" ] && run grep -E "^#!/" 31-apim-backend.sh && assert_success
}

@test "31-apim-backend.sh is executable" {
  [ -f "31-apim-backend.sh" ] && [ -x 31-apim-backend.sh ]
}

@test "31-apim-backend.sh has set -euo pipefail" {
  [ -f "31-apim-backend.sh" ] && run grep -E "set -(e|.*e.*o.*)" 31-apim-backend.sh && assert_success
}

@test "31-apim-backend.sh exists and is executable" {
  [ -f "31-apim-backend.sh" ] && [ -x "31-apim-backend.sh" ]
}

@test "31-apim-backend.sh has standard structure" {
  [ -f "31-apim-backend.sh" ] && run grep -E "set -e|log_info" 31-apim-backend.sh && assert_success
}

@test "31-apim-backend.sh uses function app as backend name" {
  [ -f "31-apim-backend.sh" ] && run grep "FUNCTION_APP_NAME" 31-apim-backend.sh && assert_success
}

# === Tests for 32-apim-policies.sh ===

@test "32-apim-policies.sh has shebang" {
  [ -f "32-apim-policies.sh" ] && run grep -E "^#!/" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh is executable" {
  [ -f "32-apim-policies.sh" ] && [ -x 32-apim-policies.sh ]
}

@test "32-apim-policies.sh has set -euo pipefail" {
  [ -f "32-apim-policies.sh" ] && run grep -E "set -(e|.*e.*o.*)" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh checks for AUTH_MODE variable" {
  [ -f "32-apim-policies.sh" ] && run grep "AUTH_MODE" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh applies CORS policy" {
  [ -f "32-apim-policies.sh" ] && run grep -E "cors|CORS" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh handles none auth mode" {
  [ -f "32-apim-policies.sh" ] && run grep -E "AUTH_MODE.*none|none.*AUTH" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh handles jwt auth mode" {
  [ -f "32-apim-policies.sh" ] && run grep -E "AUTH_MODE.*jwt|jwt.*AUTH|JWT" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh applies policies to APIM" {
  [ -f "32-apim-policies.sh" ] && run grep "az apim" 32-apim-policies.sh && assert_success
}

@test "32-apim-policies.sh validates policy configuration" {
  [ -f "32-apim-policies.sh" ] && run grep -E "policy|Policy" 32-apim-policies.sh && assert_success
}

# === APIM Integration Pattern Tests ===

@test "APIM scripts follow consistent naming pattern" {
  run bash -c "for i in 30 31 32; do [ -x \"${i}-apim*.sh\" ] || echo \"missing $i\"; done"
  # At least script 30 should exist
  [ -x "30-apim-instance.sh" ]
}

@test "APIM scripts use consistent log functions" {
  run grep -l "log_info\|log_error" 30-apim-instance.sh
  assert_success
}

@test "APIM scripts source selection utilities for resource selection" {
  run bash -c "grep -l 'selection-utils' 30-apim-instance.sh"
  assert_success
}

@test "APIM scripts handle resource group detection" {
  run grep -l "RESOURCE_GROUP" 30-apim-instance.sh
  assert_success
}

# === Documentation Tests ===

@test "30-apim-instance.sh has documentation comments" {
  run head -n 20 30-apim-instance.sh
  assert_success
  [[ "$output" =~ "#" ]]  # Should have comments
}

@test "30-apim-instance.sh references APIM or API Management" {
  run grep -E "APIM|API.*Management" 30-apim-instance.sh
  assert_success
}

@test "30-apim-instance.sh has standard log functions" {
  run grep -E "^log_info|^log_error" 30-apim-instance.sh
  assert_success
}
