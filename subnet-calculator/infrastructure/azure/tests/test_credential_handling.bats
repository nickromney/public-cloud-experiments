#!/usr/bin/env bats
#
# Tests for credential handling in authentication scripts
# Tests that 42-configure-entraid-swa.sh handles credentials safely

setup() {
  load setup

  # Set up environment
  export RESOURCE_GROUP="rg-subnet-calc"
  export STATIC_WEB_APP_NAME="swa-subnet-calc"
  export AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000"
  export AZURE_CLIENT_SECRET="test-secret~with~tildes"
}

teardown() {
  load teardown
}

# Special character handling tests

@test "42-configure-entraid-swa.sh uses printf for CLIENT_ID_SETTING" {
  run grep "printf.*AZURE_CLIENT_ID" 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses printf for CLIENT_SECRET_SETTING" {
  run grep "printf.*AZURE_CLIENT_SECRET" 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses quotes around printf variables" {
  run grep 'printf.*"%s".*AZURE_CLIENT' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh stores CLIENT_ID_SETTING in variable" {
  run grep 'CLIENT_ID_SETTING.*printf' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh stores CLIENT_SECRET_SETTING in variable" {
  run grep 'CLIENT_SECRET_SETTING.*printf' 42-configure-entraid-swa.sh
  assert_success
}

# Credential storage tests

@test "42-configure-entraid-swa.sh uses az staticwebapp appsettings set" {
  run grep 'az staticwebapp appsettings set' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh passes both CLIENT_ID and CLIENT_SECRET settings" {
  run grep 'CLIENT_ID_SETTING.*CLIENT_SECRET_SETTING' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses --setting-names parameter" {
  run grep '\-\-setting-names' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh quotes setting name variables" {
  run grep '\-\-setting-names.*".*CLIENT.*SETTING"' 42-configure-entraid-swa.sh
  assert_success
}

# Error handling for credential storage

@test "42-configure-entraid-swa.sh checks az staticwebapp appsettings set success" {
  run grep -A 3 'az staticwebapp appsettings set' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "then" ]]
}

@test "42-configure-entraid-swa.sh logs success when settings updated" {
  run grep 'App settings updated successfully' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh logs error when settings update fails" {
  run grep 'Failed to set app settings' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh exits with error code 1 when settings fail" {
  run grep -A 2 'Failed to set app settings' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

# Credential verification tests

@test "42-configure-entraid-swa.sh verifies credentials were stored" {
  run grep 'Verifying app settings' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses az staticwebapp appsettings list to verify" {
  run grep 'az staticwebapp appsettings list' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh queries for AZURE_CLIENT_ID in verification" {
  run grep 'properties.AZURE_CLIENT_ID' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh stores verification result in STORED_CLIENT_ID" {
  run grep 'STORED_CLIENT_ID.*az staticwebapp appsettings list' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh displays stored client ID in output" {
  run grep 'Client ID:.*STORED_CLIENT_ID' 42-configure-entraid-swa.sh
  assert_success
}

# Non-interactive mode tests

@test "42-configure-entraid-swa.sh detects non-interactive mode" {
  run grep 'if.*-t 0' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh selects first resource group in non-interactive mode" {
  run grep -A 3 'Non-interactive mode' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses head -1 for non-interactive selection" {
  run grep 'head -1' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh logs warning in non-interactive mode" {
  run grep 'log_warn.*Non-interactive mode' 42-configure-entraid-swa.sh
  assert_success
}

# Resource detection tests

@test "42-configure-entraid-swa.sh auto-detects single resource group" {
  run grep 'Auto-detected.*resource group' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh auto-detects single Static Web App" {
  run grep 'Auto-detected.*Static Web App' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh prompts for AZURE_CLIENT_ID if not set" {
  run grep 'Enter Entra ID Client ID' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh prompts for AZURE_CLIENT_SECRET if not set" {
  run grep 'Enter Entra ID Client Secret' 42-configure-entraid-swa.sh
  assert_success
}

# Missing resource handling

@test "42-configure-entraid-swa.sh exits if no resource groups found" {
  run grep -A 2 'No resource groups found' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "42-configure-entraid-swa.sh exits if no Static Web Apps found" {
  run grep -A 2 'No Static Web Apps found' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "42-configure-entraid-swa.sh exits if Client ID is empty" {
  run grep -A 2 'Client ID cannot be empty' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

@test "42-configure-entraid-swa.sh exits if Client Secret is empty" {
  run grep -A 2 'Client Secret cannot be empty' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 1" ]]
}

# Confirmation prompt tests

@test "42-configure-entraid-swa.sh prompts for confirmation before applying" {
  run grep 'Apply Entra ID configuration' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh defaults confirmation to yes" {
  run grep 'CONFIRM.*:-y' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh exits if user cancels" {
  run grep -B 2 -A 1 'Cancelled' 42-configure-entraid-swa.sh
  assert_success
  [[ "$output" =~ "exit 0" ]]
}

# Information display tests

@test "42-configure-entraid-swa.sh displays configuration summary" {
  run grep 'Entra ID Configuration' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh displays Static Web App name" {
  run grep 'Static Web App:.*STATIC_WEB_APP_NAME' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh displays truncated Client ID for security" {
  run grep 'AZURE_CLIENT_ID:0:20' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh does not display full Client Secret" {
  # Should NOT show full secret in logs
  run grep 'AZURE_CLIENT_SECRET:0:' 42-configure-entraid-swa.sh
  # Should not find full secret display
  [ "$status" -ne 0 ] || [[ "$output" =~ ":0:20" ]]
}

# Integration guidance tests

@test "42-configure-entraid-swa.sh provides Phase 2 deployment instructions" {
  run grep 'Phase 2.*Rebuild frontend' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh mentions VITE_AUTH_ENABLED in instructions" {
  run grep 'VITE_AUTH_ENABLED=true' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh references 20-deploy-frontend.sh" {
  run grep '20-deploy-frontend.sh' 42-configure-entraid-swa.sh
  assert_success
}

# Security best practices tests

@test "42-configure-entraid-swa.sh uses read -rsp for secret input" {
  run grep 'read -rsp' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh redirects stderr for appsettings set" {
  run grep 'az staticwebapp appsettings set.*2>/dev/null' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh handles query errors in verification" {
  run grep 'az staticwebapp appsettings list.*2>/dev/null' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh provides default for missing verification value" {
  run grep 'not set' 42-configure-entraid-swa.sh
  assert_success
}

# Library sourcing tests

@test "42-configure-entraid-swa.sh sources selection-utils.sh" {
  run grep 'source.*selection-utils.sh' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses select_resource_group function" {
  run grep 'select_resource_group' 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh uses select_static_web_app function" {
  run grep 'select_static_web_app' 42-configure-entraid-swa.sh
  assert_success
}

# AZURE_TENANT_ID tests

@test "42-configure-entraid-swa.sh detects AZURE_TENANT_ID from Azure" {
  run grep "az account show.*tenantId" 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh stores AZURE_TENANT_ID in variable" {
  run grep "AZURE_TENANT_ID.*az account show" 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh checks if AZURE_TENANT_ID is empty" {
  run bash -c "grep -B 1 'Detecting Entra ID tenant' 42-configure-entraid-swa.sh | grep -E 'if.*-z.*AZURE_TENANT_ID|z.*AZURE_TENANT_ID'"
  assert_success
}

@test "42-configure-entraid-swa.sh displays AZURE_TENANT_ID in configuration" {
  run grep "log_info.*Tenant ID" 42-configure-entraid-swa.sh
  assert_success
}

@test "42-configure-entraid-swa.sh includes AZURE_TENANT_ID in Phase 2 instructions" {
  run bash -c "grep 'AZURE_TENANT_ID' 42-configure-entraid-swa.sh | grep -E 'Phase|20-deploy'"
  assert_success
}
