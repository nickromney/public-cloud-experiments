#!/usr/bin/env bash
#
# Azure CLI mocking functions for BATS tests
# Provides mock implementations of az commands without requiring Azure login

# File to track az commands across subshells
export AZ_CALLS_FILE="${BATS_TEST_TMPDIR:-/tmp}/az_calls_$$"

# Track az commands called during tests
declare -a AZ_COMMANDS_CALLED=()
declare -a AZ_ARGS_CALLED=()

# Reset tracking arrays and file
reset_az_tracking() {
  AZ_COMMANDS_CALLED=()
  AZ_ARGS_CALLED=()
  true > "$AZ_CALLS_FILE"  # Use 'true' as no-op command for redirection
}

# Capture az command and arguments
capture_az_call() {
  local full_command="$*"
  # Write to file for cross-process tracking
  echo "$full_command" >> "$AZ_CALLS_FILE"
  # Also track in arrays for current process
  AZ_COMMANDS_CALLED+=("$full_command")
  AZ_ARGS_CALLED+=("$*")
}

# Note: We use a PATH-based mock script (tests/bin/az) instead of a bash function
# This ensures the mock works in subprocesses that scripts spawn

# Mock setup - call this in test setup()
mock_az_setup() {
  reset_az_tracking
  export AZ_MOCK_NOT_LOGGED_IN="false"
  export AZ_MOCK_RESOURCE_NOT_FOUND="false"
}

# Mock Azure CLI as logged in
mock_az_logged_in() {
  export AZ_MOCK_NOT_LOGGED_IN="false"
}

# Mock Azure CLI as not logged in
mock_az_not_logged_in() {
  export AZ_MOCK_NOT_LOGGED_IN="true"
}

# Mock resource as not found
mock_az_resource_not_found() {
  export AZ_MOCK_RESOURCE_NOT_FOUND="true"
}

# Assertions for az commands

# Assert az was called with specific command
assert_az_called() {
  local expected="$1"

  # Read calls from file (for cross-process tracking)
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    if grep -q "$expected" "$AZ_CALLS_FILE"; then
      return 0
    fi
  fi

  # Also check in-process array as fallback
  for cmd in "${AZ_COMMANDS_CALLED[@]}"; do
    if [[ "$cmd" =~ $expected ]]; then
      return 0
    fi
  done

  echo "Expected az to be called with: $expected" >&2
  echo "Actual calls:" >&2
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    cat "$AZ_CALLS_FILE" >&2
  else
    printf '%s\n' "${AZ_COMMANDS_CALLED[@]}" >&2
  fi
  return 1
}

# Assert az was called with specific argument
assert_az_arg() {
  local arg_name="$1"
  local arg_value="$2"

  # Read calls from file and check with bash pattern matching (for cross-process tracking)
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == *"$arg_name"*"$arg_value"* ]]; then
        return 0
      fi
    done < "$AZ_CALLS_FILE"
  fi

  # Also check in-process array as fallback
  for cmd in "${AZ_COMMANDS_CALLED[@]}"; do
    if [[ "$cmd" == *"$arg_name"*"$arg_value"* ]]; then
      return 0
    fi
  done

  echo "Expected az to be called with: $arg_name $arg_value" >&2
  echo "Actual calls:" >&2
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    cat "$AZ_CALLS_FILE" >&2
  else
    printf '%s\n' "${AZ_COMMANDS_CALLED[@]}" >&2
  fi
  return 1
}

# Get number of times az was called
az_call_count() {
  if [[ -f "$AZ_CALLS_FILE" ]]; then
    wc -l < "$AZ_CALLS_FILE" | tr -d ' '
  else
    echo "${#AZ_COMMANDS_CALLED[@]}"
  fi
}

# Print all az commands called (for debugging)
print_az_calls() {
  echo "=== Az commands called ===" >&2
  printf '%s\n' "${AZ_COMMANDS_CALLED[@]}" >&2
  echo "=========================" >&2
}

# Export arrays for subshells
export AZ_COMMANDS_CALLED
export AZ_ARGS_CALLED

# Export mock functions so they're available in subshells
export -f az
export -f capture_az_call
export -f reset_az_tracking
export -f mock_az_logged_in
export -f mock_az_not_logged_in
export -f mock_az_resource_not_found
export -f mock_az_setup
export -f assert_az_called
export -f assert_az_arg
export -f az_call_count
export -f print_az_calls
