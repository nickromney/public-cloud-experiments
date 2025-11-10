#!/usr/bin/env bash
#
# Mocking functions for Makefile BATS tests
# Provides mock implementations without requiring actual tools

# File to track command calls across subshells
export TERRAGRUNT_CALLS_FILE="${BATS_TEST_TMPDIR:-/tmp}/terragrunt_calls_$$"
export AZ_CALLS_FILE="${BATS_TEST_TMPDIR:-/tmp}/az_calls_$$"
export BUILD_SCRIPT_CALLS_FILE="${BATS_TEST_TMPDIR:-/tmp}/build_script_calls_$$"

# Track commands called during tests
declare -a TERRAGRUNT_COMMANDS_CALLED=()
declare -a AZ_COMMANDS_CALLED=()

# Reset tracking arrays and files
reset_tracking() {
  TERRAGRUNT_COMMANDS_CALLED=()
  AZ_COMMANDS_CALLED=()
  true > "$TERRAGRUNT_CALLS_FILE"
  true > "$AZ_CALLS_FILE"
  true > "$BUILD_SCRIPT_CALLS_FILE"
}

# Mock setup - call this in test setup()
mock_setup() {
  reset_tracking
  export MOCK_TERRAGRUNT_FAIL="false"
  export MOCK_AZ_FAIL="false"
  export MOCK_BUILD_FAIL="false"
}

# Mock terragrunt to fail
mock_terragrunt_fail() {
  export MOCK_TERRAGRUNT_FAIL="true"
}

# Mock az to fail
mock_az_fail() {
  export MOCK_AZ_FAIL="true"
}

# Mock build scripts to fail
mock_build_fail() {
  export MOCK_BUILD_FAIL="true"
}

# Assertions for terragrunt commands

# Assert terragrunt was called with specific command
assert_terragrunt_called() {
  local expected="$1"

  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    if grep -q "$expected" "$TERRAGRUNT_CALLS_FILE"; then
      return 0
    fi
  fi

  echo "Expected terragrunt to be called with: $expected" >&2
  echo "Actual calls:" >&2
  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    cat "$TERRAGRUNT_CALLS_FILE" >&2
  fi
  return 1
}

# Assert terragrunt was called with specific argument
assert_terragrunt_arg() {
  local arg_name="$1"
  local arg_value="$2"

  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == *"$arg_name"*"$arg_value"* ]]; then
        return 0
      fi
    done < "$TERRAGRUNT_CALLS_FILE"
  fi

  echo "Expected terragrunt to be called with: $arg_name $arg_value" >&2
  echo "Actual calls:" >&2
  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    cat "$TERRAGRUNT_CALLS_FILE" >&2
  fi
  return 1
}

# Assert terragrunt was called from specific directory
assert_terragrunt_called_in_dir() {
  local expected_dir="$1"

  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    # Match either full absolute path or relative path ending
    if grep -q "DIR:.*${expected_dir}" "$TERRAGRUNT_CALLS_FILE"; then
      return 0
    fi
  fi

  echo "Expected terragrunt to be called in directory: $expected_dir" >&2
  echo "Actual calls:" >&2
  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    cat "$TERRAGRUNT_CALLS_FILE" >&2
  fi
  return 1
}

# Assertions for az commands

# Assert az was called with specific command
assert_az_called() {
  local expected="$1"

  if [[ -f "$AZ_CALLS_FILE" ]]; then
    if grep -q "$expected" "$AZ_CALLS_FILE"; then
      return 0
    fi
  fi

  echo "Expected az to be called with: $expected" >&2
  echo "Actual calls:" >&2
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    cat "$AZ_CALLS_FILE" >&2
  fi
  return 1
}

# Assert az was called with specific argument
assert_az_arg() {
  local arg_name="$1"
  local arg_value="$2"

  if [[ -f "$AZ_CALLS_FILE" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == *"$arg_name"*"$arg_value"* ]]; then
        return 0
      fi
    done < "$AZ_CALLS_FILE"
  fi

  echo "Expected az to be called with: $arg_name $arg_value" >&2
  echo "Actual calls:" >&2
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    cat "$AZ_CALLS_FILE" >&2
  fi
  return 1
}

# Assertions for build scripts

# Assert build script was called
assert_build_script_called() {
  local script_name="$1"

  if [[ -f "$BUILD_SCRIPT_CALLS_FILE" ]]; then
    if grep -q "$script_name" "$BUILD_SCRIPT_CALLS_FILE"; then
      return 0
    fi
  fi

  echo "Expected build script to be called: $script_name" >&2
  echo "Actual calls:" >&2
  if [[ -f "$BUILD_SCRIPT_CALLS_FILE" ]]; then
    cat "$BUILD_SCRIPT_CALLS_FILE" >&2
  fi
  return 1
}

# Get number of times terragrunt was called
terragrunt_call_count() {
  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    wc -l < "$TERRAGRUNT_CALLS_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

# Get number of times az was called
az_call_count() {
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    wc -l < "$AZ_CALLS_FILE" | tr -d ' '
  else
    echo "0"
  fi
}

# Print all commands called (for debugging)
print_all_calls() {
  echo "=== Terragrunt commands ===" >&2
  if [[ -f "$TERRAGRUNT_CALLS_FILE" ]]; then
    cat "$TERRAGRUNT_CALLS_FILE" >&2
  fi
  echo "=== Az commands ===" >&2
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    cat "$AZ_CALLS_FILE" >&2
  fi
  echo "=== Build script calls ===" >&2
  if [[ -f "$BUILD_SCRIPT_CALLS_FILE" ]]; then
    cat "$BUILD_SCRIPT_CALLS_FILE" >&2
  fi
  echo "=========================" >&2
}

# Export arrays for subshells
export TERRAGRUNT_COMMANDS_CALLED
export AZ_COMMANDS_CALLED

# Export mock functions
export -f reset_tracking
export -f mock_setup
export -f mock_terragrunt_fail
export -f mock_az_fail
export -f mock_build_fail
export -f assert_terragrunt_called
export -f assert_terragrunt_arg
export -f assert_terragrunt_called_in_dir
export -f assert_az_called
export -f assert_az_arg
export -f assert_build_script_called
export -f terragrunt_call_count
export -f az_call_count
export -f print_all_calls
