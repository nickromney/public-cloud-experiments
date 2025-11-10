#!/usr/bin/env bats
#
# Tests for Makefile deployment commands
# Verifies deploy function-app, deploy frontend, deploy all commands

setup() {
  load setup
}

teardown() {
  load teardown
}

# Deploy function-app tests
@test "deploy function-app calls build-function-zip.sh" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_build_script_called "build-function-zip.sh"
}

@test "deploy function-app calls az functionapp deployment" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_az_called "functionapp deployment source config-zip"
}

@test "deploy function-app uses correct resource group" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_az_arg "--resource-group" "rg-test"
}

@test "deploy function-app uses --build-remote true" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_az_arg "--build-remote" "true"
}

@test "deploy function-app uses --timeout 600" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_az_arg "--timeout" "600"
}

@test "deploy function-app gets function app name from terragrunt output" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_terragrunt_called "output -raw function_app_name"
  assert_az_arg "--name" "func-test-app"
}

@test "deploy function-app shows deployment message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_output --partial "Deploying Function App"
}

@test "deploy function-app cleans up zip file after deployment" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  # Zip file should be removed
  [ ! -f "function-app.zip" ]
}

# Deploy frontend tests
@test "deploy frontend calls build-deployment-zip.sh" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_build_script_called "build-deployment-zip.sh"
}

@test "deploy frontend calls az webapp deploy" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_az_called "webapp deploy"
}

@test "deploy frontend uses correct resource group" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_az_arg "--resource-group" "rg-test"
}

@test "deploy frontend uses --type zip" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_az_arg "--type" "zip"
}

@test "deploy frontend gets web app name from terragrunt output" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_terragrunt_called "output -raw web_app_name"
  assert_az_arg "--name" "web-test-app"
}

@test "deploy frontend gets API URL from terragrunt output" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_terragrunt_called "output -raw apim_api_url"
  # API_BASE_URL should be set when calling build script
  assert_output --partial "API_BASE_URL"
}

@test "deploy frontend shows deployment message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_output --partial "Deploying React Frontend"
}

@test "deploy frontend cleans up zip file after deployment" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  # Zip file should be removed
  [ ! -f "react-app.zip" ]
}

# Deploy all tests
@test "deploy all deploys both function and frontend" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy all

  assert_success
  assert_build_script_called "build-function-zip.sh"
  assert_build_script_called "build-deployment-zip.sh"
}

@test "deploy all calls both az functionapp and webapp commands" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy all

  assert_success
  assert_az_called "functionapp deployment source config-zip"
  assert_az_called "webapp deploy"
}

@test "deploy all shows completion message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy all

  assert_success
  assert_output --partial "Deploying Function App"
  assert_output --partial "Deploying React Frontend"
}

# Error handling in deployment tests
@test "deploy function-app fails gracefully if build fails" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_BUILD_FAIL="true"

  run make subnet-calc react-apim deploy function-app

  assert_failure
  assert_output --partial "Build script failed"
}

@test "deploy frontend fails gracefully if build fails" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_BUILD_FAIL="true"

  run make subnet-calc react-apim deploy frontend

  assert_failure
  assert_output --partial "Build script failed"
}

@test "deploy function-app fails gracefully if az command fails" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_AZ_FAIL="true"

  run make subnet-calc react-apim deploy function-app

  assert_failure
}

@test "deploy frontend fails gracefully if az command fails" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_AZ_FAIL="true"

  run make subnet-calc react-apim deploy frontend

  assert_failure
}

# Component-specific tests
@test "deploy without component shows usage" {
  run make subnet-calc react-apim deploy

  assert_failure
  assert_output --partial "Usage:"
  assert_output --partial "deploy"
}

@test "deploy with invalid component shows error" {
  run make subnet-calc react-apim deploy invalid-component

  assert_failure
}

# Build script parameters tests
@test "build-function-zip.sh receives correct output path" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  # Check that build script was called with zip path
  run grep -q "function-app.zip" "$BUILD_SCRIPT_CALLS_FILE"
  assert_success
}

@test "build-deployment-zip.sh receives correct output path" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  # Check that build script was called with zip path
  run grep -q "react-app.zip" "$BUILD_SCRIPT_CALLS_FILE"
  assert_success
}
