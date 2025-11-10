#!/usr/bin/env bash
#
# Teardown run after each BATS test
# Cleans up test artifacts and resets state

# Cleanup temporary test directory
if [ -n "${BATS_TEST_TMPDIR:-}" ] && [ -d "$BATS_TEST_TMPDIR" ]; then
  rm -rf "$BATS_TEST_TMPDIR"
fi

# Clear tracking files
if [ -n "${MAKE_CALLS_FILE:-}" ] && [ -f "$MAKE_CALLS_FILE" ]; then
  rm -f "$MAKE_CALLS_FILE"
fi

if [ -n "${TERRAGRUNT_CALLS_FILE:-}" ] && [ -f "$TERRAGRUNT_CALLS_FILE" ]; then
  rm -f "$TERRAGRUNT_CALLS_FILE"
fi

if [ -n "${AZ_CALLS_FILE:-}" ] && [ -f "$AZ_CALLS_FILE" ]; then
  rm -f "$AZ_CALLS_FILE"
fi
