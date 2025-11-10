#!/usr/bin/env bats
#
# Tests for Makefile infrastructure lifecycle commands
# Verifies init, plan, apply, destroy, validate commands

setup() {
  load setup
}

teardown() {
  load teardown
}

# Init command tests
@test "init command runs terragrunt init with upgrade flag" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim init

  assert_success
  assert_terragrunt_called "init"
  assert_terragrunt_arg "-upgrade" ""
}

@test "init command shows initialization message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim init

  assert_success
  assert_output --partial "Initializing"
}

# Plan command tests
@test "plan command runs terragrunt init then plan" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim plan

  assert_success
  assert_terragrunt_called "init"
  assert_terragrunt_called "plan"
}

@test "plan command shows planning message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim plan

  assert_success
  assert_output --partial "Planning"
}

@test "plan command shows terragrunt output" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim plan

  assert_success
  assert_output --partial "OpenTofu will perform the following actions"
}

# Apply command tests
@test "apply command runs terragrunt init then apply" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim apply

  assert_success
  assert_terragrunt_called "init"
  assert_terragrunt_called "apply"
}

@test "apply command shows applying message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim apply

  assert_success
  assert_output --partial "Applying"
}

@test "apply command for APIM stack shows timing note" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim apply

  assert_success
  assert_output --partial "APIM provisioning takes"
  assert_output --partial "37 minutes"
}

@test "apply command for internal-apim stack shows timing note" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc internal-apim apply

  assert_success
  assert_output --partial "APIM provisioning takes"
}

@test "apply command for non-APIM stack does not show timing note" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-webapp apply

  assert_success
  # Should not mention APIM timing
  refute_output --partial "APIM provisioning takes"
}

# Destroy command tests
@test "destroy command runs terragrunt destroy" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim destroy

  assert_success
  assert_terragrunt_called "destroy"
}

@test "destroy command shows destroying message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim destroy

  assert_success
  assert_output --partial "Destroying"
}

# Validate command tests
@test "validate command runs terragrunt validate" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_terragrunt_called "validate"
}

@test "validate command shows validating message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_output --partial "Validating"
}

@test "validate command shows success message" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_output --partial "Success"
}

# Clean command tests
@test "clean cache removes .terragrunt-cache directory" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  # Create a mock cache directory
  mkdir -p personal-sub/subnet-calc-react-webapp-apim/.terragrunt-cache
  touch personal-sub/subnet-calc-react-webapp-apim/.terragrunt-cache/test-file

  run make subnet-calc react-apim clean cache

  assert_success
  assert_output --partial "Cleaning"
  # Cache should be removed
  [ ! -d personal-sub/subnet-calc-react-webapp-apim/.terragrunt-cache ]
}

# Unlock command tests
@test "unlock command requires lock ID as positional argument" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim unlock

  assert_failure
  assert_output --partial "Lock ID required"
  assert_output --partial "unlock <lock-id>"
}

@test "unlock command with lock ID as positional argument runs force-unlock" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim unlock test-lock-123

  assert_success
  assert_terragrunt_called "force-unlock"
  assert_terragrunt_arg "test-lock-123" ""
  assert_terragrunt_arg "-force" ""
}

# Environment variable propagation tests
@test "PERSONAL_SUB_REGION is passed to all commands" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"
  export PERSONAL_SUB_REGION="centralus"

  run make subnet-calc react-apim validate

  assert_success
  assert_env_equals "PERSONAL_SUB_REGION" "centralus"
}

@test "RESOURCE_GROUP defaults to rg-subnet-calc" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_env_equals "RESOURCE_GROUP" "rg-test"
}

# Directory context tests
@test "commands are executed in correct stack directory" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-apim validate

  assert_success
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-react-webapp-apim"
}

@test "different stacks use different directories" {
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  run make subnet-calc react-webapp validate
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-react-webapp"

  reset_tracking

  run make subnet-calc internal-apim validate
  assert_terragrunt_called_in_dir "personal-sub/subnet-calc-internal-apim"
}
