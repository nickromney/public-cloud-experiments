#!/usr/bin/env bats
#
# Tests for Makefile command routing and stack name mapping
# Verifies hierarchical command structure: make <project> <stack> <verb> [component]

setup() {
  load setup
}

teardown() {
  load teardown
}

# Stack name mapping tests
@test "react-apim maps to personal-sub/subnet-calc-react-webapp-apim" {
  # Override SCRIPTS_DIR to use mock scripts
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-react-webapp-apim"
}

@test "react-webapp maps to personal-sub/subnet-calc-react-webapp" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-webapp validate

  assert_success
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-react-webapp"
}

@test "internal-apim maps to personal-sub/subnet-calc-internal-apim" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc internal-apim validate

  assert_success
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-internal-apim"
}

@test "static-web-apps maps to personal-sub/subnet-calc-static-web-apps" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc static-web-apps validate

  assert_success
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-static-web-apps"
}

# Invalid stack tests
@test "invalid stack name shows error" {
  run make subnet-calc invalid-stack plan

  assert_failure
  assert_output --partial "Unknown stack"
}

@test "missing stack argument shows usage" {
  run make subnet-calc

  assert_failure
  assert_output --partial "Usage"
}

@test "missing verb argument shows usage" {
  run make subnet-calc react-apim

  assert_failure
  assert_output --partial "Usage"
}

# Verb routing tests
@test "init verb routes to _exec-init" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim init

  assert_success
  assert_terragrunt_called "init"
  assert_terragrunt_arg "-upgrade" ""
}

@test "plan verb routes to _exec-plan" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim plan

  assert_success
  assert_terragrunt_called "plan"
}

@test "apply verb routes to _exec-apply" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim apply

  assert_success
  assert_terragrunt_called "apply"
}

@test "destroy verb routes to _exec-destroy" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim destroy

  assert_success
  assert_terragrunt_called "destroy"
}

@test "validate verb routes to _exec-validate" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_terragrunt_called "validate"
}

# Component argument tests
@test "deploy function-app routes correctly" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy function-app

  assert_success
  assert_build_script_called "build-function-zip.sh"
  assert_az_called "functionapp deployment source config-zip"
}

@test "deploy frontend routes correctly" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy frontend

  assert_success
  assert_build_script_called "build-deployment-zip.sh"
  assert_az_called "webapp deploy"
}

@test "deploy all routes to both function and frontend" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim deploy all

  assert_success
  assert_build_script_called "build-function-zip.sh"
  assert_build_script_called "build-deployment-zip.sh"
  assert_az_called "functionapp deployment source config-zip"
  assert_az_called "webapp deploy"
}

# Multiple project support tests
@test "subnet-calc project is recognized" {
  run make subnet-calc react-apim help 2>&1 || true

  # Should not show "unknown project" error
  assert_output_not_contains "unknown project"
}

# Argument suppression tests
@test "make suppresses argument as target names" {
  # This tests that extra arguments like 'react-apim' don't cause "No rule to make target" errors
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  # Should not see "No rule to make target 'react-apim'"
  assert_output_not_contains "No rule to make target"
}

# PERSONAL_SUB_REGION propagation tests
@test "PERSONAL_SUB_REGION is passed to terragrunt" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export PERSONAL_SUB_REGION="westus2"

  run make subnet-calc react-apim validate

  assert_success
  # The mock terragrunt will have this in its environment
  assert_env_equals "PERSONAL_SUB_REGION" "westus2"
}

# Color output tests
@test "help command shows colored output" {
  run make help

  assert_success
  # Check for ANSI color codes (matches [1;33m format)
  assert_output --regexp "\[.*m"
}

@test "error messages show in yellow" {
  run make subnet-calc invalid-stack plan

  assert_failure
  # Should contain color codes (matches [1;33m format)
  assert_output --regexp "\[1;33m"
}
