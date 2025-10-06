#!/usr/bin/env bash
#
# Teardown run after each BATS test
# Cleans up test artifacts

# Remove temporary test directory
if [ -d "$BATS_TEST_TMPDIR" ]; then
  rm -rf "$BATS_TEST_TMPDIR"
fi

# Reset az mocking state
reset_az_tracking
unset AZ_MOCK_NOT_LOGGED_IN
unset AZ_MOCK_RESOURCE_NOT_FOUND
