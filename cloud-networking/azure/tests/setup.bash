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

# Add mock bin directory to PATH (before real az)
export PATH="${BATS_TEST_DIRNAME}/bin:$PATH"

# Change to script directory for tests
cd "${BATS_TEST_DIRNAME}/.." || exit 1

# Create temporary directory for test artifacts
export BATS_TEST_TMPDIR="${BATS_TMPDIR}/azure-test-$$"
mkdir -p "$BATS_TEST_TMPDIR"

# Initialize mocks
mock_az_setup

# Export BATS_TEST_DIRNAME so mock az script can find fixtures
export BATS_TEST_DIRNAME
