#!/usr/bin/env bash
#
# Setup run before each BATS test
# Loads support libraries and initializes test environment

# Load BATS support libraries if available
if [ -f "/usr/local/lib/bats-support/load.bash" ]; then
  load '/usr/local/lib/bats-support/load.bash'
elif [ -f "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash" ]; then
  load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash"
fi

if [ -f "/usr/local/lib/bats-assert/load.bash" ]; then
  load '/usr/local/lib/bats-assert/load.bash'
elif [ -f "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load.bash" ]; then
  load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load.bash"
fi

# Load custom helpers and mocks
load "${BATS_TEST_DIRNAME}/helpers.bash"
load "${BATS_TEST_DIRNAME}/mocks.bash"

# Add mock bin directory to PATH (before real commands)
export PATH="${BATS_TEST_DIRNAME}/bin:$PATH"

# Change to Makefile directory for tests
cd "${BATS_TEST_DIRNAME}/.." || exit 1

# Create temporary directory for test artifacts
export BATS_TEST_TMPDIR="${BATS_TMPDIR}/terragrunt-makefile-test-$$"
mkdir -p "$BATS_TEST_TMPDIR"

# Set required environment variables for Makefile
export PERSONAL_SUB_REGION="uksouth"
export RESOURCE_GROUP="rg-test"
export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
export TF_BACKEND_RG="rg-tfstate"
export TF_BACKEND_SA="sttfstate"
export TF_BACKEND_CONTAINER="tfstate"

# Initialize mocks
mock_setup

# Export BATS_TEST_DIRNAME so mock scripts can find fixtures
export BATS_TEST_DIRNAME
