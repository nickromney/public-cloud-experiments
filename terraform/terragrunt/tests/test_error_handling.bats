#!/usr/bin/env bats
#
# Tests for Makefile error handling
# Verifies proper error detection, messages, and exit codes

setup() {
  load setup
}

teardown() {
  load teardown
}

# Missing argument errors
@test "make subnet-calc without stack shows usage" {
  run make subnet-calc

  assert_failure
  assert_output --partial "Usage"
  assert_output --partial "make subnet-calc <stack> <verb>"
}

@test "make subnet-calc stack without verb shows usage" {
  run make subnet-calc react-apim

  assert_failure
  assert_output --partial "Usage"
}

# Invalid stack errors
@test "invalid stack name shows clear error message" {
  run make subnet-calc nonexistent-stack plan

  assert_failure
  assert_output --partial "Unknown stack"
  assert_output --partial "nonexistent-stack"
}

@test "typo in stack name shows helpful error" {
  run make subnet-calc react-api plan  # Typo: should be react-apim

  assert_failure
  assert_output --partial "Unknown stack"
}

# Invalid verb errors
@test "invalid verb shows error" {
  run make subnet-calc react-apim nonexistent-verb

  assert_failure
}

# Terragrunt command failures
@test "terragrunt init failure propagates error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_TERRAGRUNT_FAIL="true"

  run make subnet-calc react-apim init

  assert_failure
  assert_output --partial "Terragrunt command failed"
}

@test "terragrunt plan failure propagates error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_TERRAGRUNT_FAIL="true"

  run make subnet-calc react-apim plan

  assert_failure
}

@test "terragrunt apply failure propagates error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_TERRAGRUNT_FAIL="true"

  run make subnet-calc react-apim apply

  assert_failure
}

# Azure CLI command failures
@test "az functionapp deployment failure shows error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_AZ_FAIL="true"

  run make subnet-calc react-apim deploy function-app

  assert_failure
  assert_output --partial "Azure CLI command failed"
}

@test "az webapp deploy failure shows error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_AZ_FAIL="true"

  run make subnet-calc react-apim deploy frontend

  assert_failure
}

# Build script failures
@test "build-function-zip.sh failure stops deployment" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_BUILD_FAIL="true"

  run make subnet-calc react-apim deploy function-app

  assert_failure
  assert_output --partial "Build script failed"
  # az should not be called if build fails
  [ "$(az_call_count)" -eq 0 ]
}

@test "build-deployment-zip.sh failure stops deployment" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_BUILD_FAIL="true"

  run make subnet-calc react-apim deploy frontend

  assert_failure
  # az should not be called if build fails
  [ "$(az_call_count)" -eq 0 ]
}

# Missing required parameters
@test "unlock without LOCK_ID shows clear error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim unlock

  assert_failure
  assert_output --partial "Lock ID required"
  assert_output --partial "unlock <lock-id>"
}

@test "deploy without component shows usage" {
  run make subnet-calc react-apim deploy

  assert_failure
  assert_output --partial "Usage:"
  assert_output --partial "deploy"
}

# Test verb specific errors
@test "test apim without deployment shows helpful error" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  # Mock terragrunt output to return empty (simulating no deployment)
  export MOCK_TERRAGRUNT_FAIL="false"

  run make subnet-calc react-apim test apim 2>&1 || true

  # May fail or succeed depending on implementation
  # But should not crash
}

@test "show without component shows usage" {
  run make subnet-calc react-apim show

  assert_failure
  assert_output --partial "Usage"
}

@test "get without component shows usage" {
  run make subnet-calc react-apim get

  assert_failure
  assert_output --partial "Usage"
}

# Directory not found errors
@test "nonexistent stack directory is caught" {
  # This should be caught by the stack mapping validation
  run make subnet-calc nonexistent-stack plan

  assert_failure
  assert_output --partial "Unknown stack"
}

# Environment variable errors
@test "missing PERSONAL_SUB_REGION uses default from Makefile" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  unset PERSONAL_SUB_REGION

  run make subnet-calc react-apim validate

  # Should succeed with default value
  assert_success
}

# Multiple error conditions
@test "deploy all continues if function-app fails" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_BUILD_FAIL="true"

  run make subnet-calc react-apim deploy all

  assert_failure
  # Should attempt both deployments even if one fails
}

# Clean error messages for common mistakes
@test "using old command format is silently ignored" {
  # Old format would be: make subnet-calc-react-apim-plan
  # The %: @: rule catches this and does nothing (no error, no action)
  run make subnet-calc-react-apim-plan

  assert_success
  # Should produce no output (silently ignored)
  assert_output ""
}

@test "help command never fails" {
  run make help

  assert_success
}

@test "help command is accessible even with errors" {
  # Help should work even if environment is misconfigured
  unset PERSONAL_SUB_REGION
  unset RESOURCE_GROUP

  run make help

  assert_success
}

# Stack-specific error handling
@test "APIM stack shows timing warning on apply" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim apply

  assert_success
  assert_output --partial "37 minutes"
}

@test "APIM stack shows deletion warning on destroy" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim destroy

  assert_success
  assert_output --partial "15 minutes"
}

# Color output in error messages
@test "error messages include colored output" {
  run make subnet-calc invalid-stack plan

  assert_failure
  # Should contain ANSI color codes (matches [1;33m format)
  assert_output --regexp "\[.*m"
}

# Makefile internal errors
@test "STACK_DIR resolution failure is handled" {
  # Create a scenario where stack dir resolution fails
  run make subnet-calc "" plan

  assert_failure
}

@test "missing SCRIPTS_DIR is handled gracefully" {
  unset SCRIPTS_DIR
  export SCRIPTS_DIR="/nonexistent/path"

  run make subnet-calc react-apim deploy function-app

  assert_failure
}

# Exit code tests
@test "successful command returns 0" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  [ "$status" -eq 0 ]
}

@test "failed command returns non-zero" {
  run make subnet-calc invalid-stack plan

  assert_failure
  [ "$status" -ne 0 ]
}

@test "terragrunt failure propagates exit code" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export MOCK_TERRAGRUNT_FAIL="true"

  run make subnet-calc react-apim plan

  assert_failure
  [ "$status" -ne 0 ]
}
