#!/usr/bin/env bats
#
# Tests for backend linking scripts
# Tests that 40-link-backend-to-swa.sh links SWA to Function App correctly

setup() {
  load setup

  # Set up environment for backend linking script
  export RESOURCE_GROUP="rg-subnet-calc"
  export STATIC_WEB_APP_NAME="swa-subnet-calc"
  export FUNCTION_APP_NAME="func-subnet-calc"
  export REGION="eastus"
}

teardown() {
  load teardown
}

# === Script Structure Tests ===

@test "40-link-backend-to-swa.sh has shebang" {
  run grep -E "^#!/" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh is executable" {
  [ -x 40-link-backend-to-swa.sh ]
}

@test "40-link-backend-to-swa.sh has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh defines log_info function" {
  run grep -q "^log_info()" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh defines log_error function" {
  run grep -q "^log_error()" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh defines log_step function" {
  run grep -q "^log_step()" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh defines log_warn function" {
  run grep -q "^log_warn()" 40-link-backend-to-swa.sh
  assert_success
}

# === Library Sourcing Tests ===

@test "40-link-backend-to-swa.sh sources selection-utils.sh" {
  run grep "source.*selection-utils.sh" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh sources map-swa-region.sh" {
  run grep "source.*map-swa-region" 40-link-backend-to-swa.sh
  assert_success
}

# === Azure CLI Interaction Tests ===

@test "40-link-backend-to-swa.sh checks Azure CLI login" {
  run grep "az account show" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh exits if not logged in" {
  run grep -A 2 "az account show" 40-link-backend-to-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

# === Resource Detection Tests ===

@test "40-link-backend-to-swa.sh auto-detects single resource group" {
  run bash -c "grep -E 'az group list.*length|RG_COUNT' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh uses select_resource_group function" {
  run grep "select_resource_group" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh auto-detects single Static Web App" {
  run bash -c "grep -E 'az staticwebapp list|SWA_COUNT' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh uses select_static_web_app function" {
  run grep "select_static_web_app" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh auto-detects single Function App" {
  run bash -c "grep -E 'az functionapp list|FUNC_COUNT' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh uses select_function_app function" {
  run grep "select_function_app" 40-link-backend-to-swa.sh
  assert_success
}

# === Region Mapping Tests ===

@test "40-link-backend-to-swa.sh validates REGION parameter" {
  run grep "REGION" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh uses map_swa_region function" {
  run grep "map_swa_region" 40-link-backend-to-swa.sh
  assert_success
}

@test "40-link-backend-to-swa.sh handles region mapping" {
  run bash -c "grep -A 2 'map_swa_region' 40-link-backend-to-swa.sh | head -5"
  assert_success
}

# === Backend Configuration Tests ===

@test "40-link-backend-to-swa.sh manages backend linking" {
  run bash -c "grep -E 'backends|backend' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh links function app to SWA" {
  run bash -c "grep -E 'az staticwebapp.*backend|link.*backend' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh configures API location" {
  run bash -c "grep -E 'location|api.*path|API_PATH' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh verifies backend link success" {
  run bash -c "grep -E 'backend.*success|link.*success|verify' 40-link-backend-to-swa.sh"
  assert_success
}

# === Error Handling Tests ===

@test "40-link-backend-to-swa.sh handles backend link failures" {
  run bash -c "grep -E 'Failed.*link|link.*[Ff]ailed' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh validates Static Web App exists" {
  run bash -c "grep -E 'No Static|SWA.*found|found.*SWA' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh validates Function App exists" {
  run bash -c "grep -E 'No Function|Function.*found|found.*Function' 40-link-backend-to-swa.sh"
  assert_success
}

# === Logging Tests ===

@test "40-link-backend-to-swa.sh logs configuration details" {
  run bash -c "grep -E 'log_info.*Static|log_info.*Function|log_step' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh logs backend URL after linking" {
  run bash -c "grep -E 'log_info.*[Uu]rl|log_info.*backend' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh provides next steps" {
  run bash -c "grep -E 'next|[Nn]ext step|test|Test' 40-link-backend-to-swa.sh"
  assert_success
}

# === Documentation Tests ===

@test "40-link-backend-to-swa.sh documents usage" {
  run head -n 30 40-link-backend-to-swa.sh
  assert_success
  [[ "$output" =~ "Usage" ]]
}

@test "40-link-backend-to-swa.sh documents all parameters" {
  run bash -c "grep -E '^#.*STATIC_WEB_APP|^#.*FUNCTION_APP|^#.*REGION' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh documents requirements" {
  run bash -c "grep -E '^#.*[Rr]equirement|^#.*[Rr]equire|^#.*must' 40-link-backend-to-swa.sh"
  assert_success
}

@test "40-link-backend-to-swa.sh documents notes about security" {
  run bash -c "grep -E '^#.*Note|^#.*security|^#.*IP.*restrict' 40-link-backend-to-swa.sh"
  assert_success
}

# === Integration Pattern Tests ===

@test "40-link-backend-to-swa.sh follows deployment script conventions" {
  # Check for standard patterns
  run bash -c "grep -E 'SCRIPT_DIR|source.*lib' 40-link-backend-to-swa.sh"
  assert_success
}

@test "Backend linking references security configuration script" {
  run bash -c "grep -i '45.*restrict\\|restrict.*45\\|IP.*restrict' 40-link-backend-to-swa.sh"
  assert_success
}
