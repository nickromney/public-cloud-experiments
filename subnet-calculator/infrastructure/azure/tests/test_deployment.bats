#!/usr/bin/env bats
#
# Tests for function deployment scripts
# Tests that 21-deploy-function.sh handles deployment correctly

setup() {
  load setup

  # Set up environment for deployment script
  export RESOURCE_GROUP="rg-subnet-calc"
  export FUNCTION_APP_NAME="func-subnet-calc"
  export PROJECT_ROOT="${BATS_TEST_TMPDIR}/project"
  export FUNCTION_DIR="${PROJECT_ROOT}/subnet-calculator/api-fastapi-azure-function"

  # Create mock function directory structure
  mkdir -p "${FUNCTION_DIR}"
  mkdir -p "${FUNCTION_DIR}/__pycache__"
  mkdir -p "${FUNCTION_DIR}/tests"

  # Create mock requirements.txt
  echo "fastapi==0.104.1" > "${FUNCTION_DIR}/requirements.txt"
  echo "azure-functions" >> "${FUNCTION_DIR}/requirements.txt"

  # Create mock function code
  echo "from azure.functions import AsgiRequest, AsgiResponse" > "${FUNCTION_DIR}/function_app.py"

  # Create mock .venv (should be excluded)
  mkdir -p "${FUNCTION_DIR}/.venv"
  touch "${FUNCTION_DIR}/.venv/pyvenv.cfg"

  # Create mock test file (should be excluded)
  echo "def test_something(): pass" > "${FUNCTION_DIR}/tests/test_api.py"
}

teardown() {
  load teardown
}

# Script structure tests

@test "21-deploy-function.sh has shebang" {
  run grep -E "^#!/" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh is executable" {
  [ -x 21-deploy-function.sh ]
}

@test "21-deploy-function.sh has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh sources selection utilities" {
  run grep "source.*selection-utils.sh" 21-deploy-function.sh
  assert_success
}

# Configuration and variable tests

@test "21-deploy-function.sh has DISABLE_AUTH variable with false default" {
  run grep 'DISABLE_AUTH.*false' 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh uses DISABLE_AUTH variable correctly" {
  run grep -E 'DISABLE_AUTH.*true|DISABLE_AUTH.*false' 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh defines log_info function" {
  run grep -q "^log_info()" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh defines log_error function" {
  run grep -q "^log_error()" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh defines log_warn function" {
  run grep -q "^log_warn()" 21-deploy-function.sh
  assert_success
}

# Azure CLI interaction tests

@test "21-deploy-function.sh checks Azure CLI login status" {
  run grep "az account show" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh exits if not logged in to Azure" {
  run grep -A 2 "az account show" 21-deploy-function.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "21-deploy-function.sh validates FUNCTION_APP_NAME exists" {
  run grep "az functionapp show" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh auto-detects single Function App" {
  run grep -E "az functionapp list.*query.*length" 21-deploy-function.sh
  assert_success
}

# Deployment configuration tests

@test "21-deploy-function.sh references Project Root correctly" {
  run grep "PROJECT_ROOT" 21-deploy-function.sh
  assert_success
  [[ "$output" =~ "SCRIPT_DIR" ]]
}

@test "21-deploy-function.sh has FUNCTION_DIR definition" {
  run grep "FUNCTION_DIR.*PROJECT_ROOT" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh checks FUNCTION_DIR exists before deployment" {
  run grep -E "if.*-d.*FUNCTION_DIR|FUNCTION_DIR.*-d" 21-deploy-function.sh
  assert_success
}

@test "21-deploy-function.sh uses deployment method (zip or git)" {
  run bash -c "grep -E 'az functionapp deployment|func azure' 21-deploy-function.sh"
  assert_success
}

# Error handling tests

@test "21-deploy-function.sh has error handling" {
  run bash -c "grep -E 'if|exit' 21-deploy-function.sh"
  assert_success
}

@test "21-deploy-function.sh logs deployment progress" {
  run grep -E 'log_info.*[Dd]eploying|log_step' 21-deploy-function.sh
  assert_success
}

# Documentation tests

@test "21-deploy-function.sh documents usage" {
  run head -n 20 21-deploy-function.sh
  assert_success
  [[ "$output" =~ "Usage" ]]
}

@test "21-deploy-function.sh documents environment variables" {
  run grep -E "^#.*DISABLE_AUTH|FUNCTION_APP_NAME|RESOURCE_GROUP" 21-deploy-function.sh
  assert_success
}
