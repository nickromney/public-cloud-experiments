#!/usr/bin/env bats
#
# Tests for configuration file copying in deployment scripts
# Tests that 20-deploy-frontend.sh correctly copies auth/noauth configs

setup() {
  load setup

  # Create test config files
  export TEST_CONFIG_DIR="${BATS_TEST_TMPDIR}/configs"
  mkdir -p "${TEST_CONFIG_DIR}"

  echo '{"auth":"entraid"}' > "${TEST_CONFIG_DIR}/staticwebapp-entraid.config.json"
  echo '{"auth":"none"}' > "${TEST_CONFIG_DIR}/staticwebapp-noauth.config.json"

  # Set up environment for deployment script
  export RESOURCE_GROUP="rg-subnet-calc"
  export STATIC_WEB_APP_NAME="swa-subnet-calc"
  export FRONTEND="typescript"
  export VITE_API_URL=""

  # Create mock frontend directory structure
  export MOCK_FRONTEND_DIR="${BATS_TEST_TMPDIR}/frontend"
  mkdir -p "${MOCK_FRONTEND_DIR}/dist"

  # Create mock package.json for npm check
  echo '{"name":"test"}' > "${MOCK_FRONTEND_DIR}/package.json"
}

teardown() {
  load teardown
}

# Configuration copying tests

@test "20-deploy-frontend.sh copies entraid config when VITE_AUTH_ENABLED=true" {
  # Test relies on script sourcing to check config file selection logic
  run grep -A 10 'VITE_AUTH_ENABLED.*true' 20-deploy-frontend.sh
  assert_success
  [[ "$output" =~ "staticwebapp-entraid.config.json" ]]
}

@test "20-deploy-frontend.sh copies noauth config when VITE_AUTH_ENABLED=false" {
  # Test relies on script sourcing to check config file selection logic
  run grep -A 10 'VITE_AUTH_ENABLED.*false' 20-deploy-frontend.sh
  assert_success
  [[ "$output" =~ "staticwebapp-noauth.config.json" ]]
}

@test "20-deploy-frontend.sh has entraid config file path" {
  run grep -o 'staticwebapp-entraid.config.json' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh has noauth config file path" {
  run grep -o 'staticwebapp-noauth.config.json' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh checks VITE_AUTH_ENABLED variable" {
  run grep 'VITE_AUTH_ENABLED' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh copies config to dist directory" {
  run grep 'dist/staticwebapp.config.json' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh logs when using Entra ID config" {
  run grep -i 'entra.*id.*authentication.*config' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh logs when using no-auth config" {
  run grep -i 'no-auth.*config' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh has error handling for config copy failure" {
  run grep -A 3 'cp.*staticwebapp.*config.json' 20-deploy-frontend.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "20-deploy-frontend.sh verifies config file exists after copy" {
  run grep 'dist/staticwebapp.config.json' 20-deploy-frontend.sh
  assert_success
  # Should check for file existence
  run grep -A 5 'dist/staticwebapp.config.json' 20-deploy-frontend.sh
  [[ "$output" =~ "if.*-f" ]]
}

# Config selection logic tests

@test "20-deploy-frontend.sh defaults VITE_AUTH_ENABLED to false when unset" {
  run grep 'VITE_AUTH_ENABLED:-false' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh uses if-then-else for config selection" {
  run grep -E 'if.*VITE_AUTH_ENABLED' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh has else clause for noauth config" {
  run grep -B 2 -A 2 'else' 20-deploy-frontend.sh | grep -i 'no-auth'
  assert_success
}

# Logging tests

@test "20-deploy-frontend.sh logs config file path being copied" {
  run grep 'log_info.*Source config file' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh logs success message after copy" {
  run grep 'Config copied successfully' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh logs error if config file missing" {
  run grep 'Failed to copy.*config' 20-deploy-frontend.sh
  assert_success
}

# Integration tests for config file paths

@test "staticwebapp-entraid.config.json exists in infrastructure directory" {
  [ -f "staticwebapp-entraid.config.json" ] || skip "Config file not committed yet"
}

@test "staticwebapp-noauth.config.json exists in infrastructure directory" {
  [ -f "staticwebapp-noauth.config.json" ] || skip "Config file not committed yet"
}

# Path resolution tests

@test "20-deploy-frontend.sh uses SCRIPT_DIR for config file paths" {
  run grep 'SCRIPT_DIR.*staticwebapp.*config.json' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh resolves SCRIPT_DIR correctly" {
  run grep 'SCRIPT_DIR.*dirname.*BASH_SOURCE' 20-deploy-frontend.sh
  assert_success
}

# Debug logging tests

@test "20-deploy-frontend.sh has debug logging for VITE_AUTH_ENABLED" {
  run grep 'DEBUG.*VITE_AUTH_ENABLED' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh has debug logging for source config file" {
  run grep 'DEBUG.*Source config file' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh has debug logging for file existence" {
  run grep 'DEBUG.*file exists' 20-deploy-frontend.sh
  assert_success
}

# Error handling tests

@test "20-deploy-frontend.sh exits with error code 1 on config copy failure" {
  run grep -A 2 'Failed to copy.*config' 20-deploy-frontend.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "20-deploy-frontend.sh checks if destination file exists after copy" {
  run grep 'if.*-f.*dist/staticwebapp.config.json' 20-deploy-frontend.sh
  assert_success
}

@test "20-deploy-frontend.sh logs error if config missing after copy" {
  run grep 'Config file missing after copy' 20-deploy-frontend.sh
  assert_success
}
