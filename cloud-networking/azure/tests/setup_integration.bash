#!/usr/bin/env bash
#
# Setup for integration tests - NO MOCKS
# Uses real Azure CLI

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

# Load custom helpers only (NOT mocks)
load "${BATS_TEST_DIRNAME}/helpers.bash"

# Change to script directory for tests
cd "${BATS_TEST_DIRNAME}/.." || exit 1

# Create temporary directory for test artifacts
export BATS_TEST_TMPDIR="${BATS_TMPDIR}/azure-integration-test-$$"
mkdir -p "$BATS_TEST_TMPDIR"
