#!/usr/bin/env bash
#
# Helper functions and assertions for BATS tests
#
# Note: $status and $output are provided by BATS's run command
# shellcheck disable=SC2154

# Assert script has set -euo pipefail
assert_has_set_errexit() {
  local script="$1"
  run grep -E "set -(e|.*e.*o.*)" "$script"
  [ "$status" -eq 0 ] || {
    echo "Script $script should have 'set -e' or 'set -euo pipefail'" >&2
    return 1
  }
}

# Assert script is executable
assert_executable() {
  local script="$1"
  [ -x "$script" ] || {
    echo "Script $script should be executable" >&2
    return 1
  }
}

# Assert script has proper shebang
assert_has_shebang() {
  local script="$1"
  run head -n 1 "$script"
  [[ "$output" =~ ^#!/ ]] || {
    echo "Script $script should have a shebang (#!/...)" >&2
    return 1
  }
}

# Assert output contains pattern
assert_output_contains() {
  local pattern="$1"
  [[ "$output" =~ $pattern ]] || {
    echo "Expected output to contain: $pattern" >&2
    echo "Actual output: $output" >&2
    return 1
  }
}

# Assert output does not contain pattern
assert_output_not_contains() {
  local pattern="$1"
  [[ ! "$output" =~ $pattern ]] || {
    echo "Expected output NOT to contain: $pattern" >&2
    echo "Actual output: $output" >&2
    return 1
  }
}

# Assert file contains pattern
assert_file_contains() {
  local file="$1"
  local pattern="$2"
  # Use -- to prevent grep from interpreting pattern as option
  run grep -q -- "$pattern" "$file"
  [ "$status" -eq 0 ] || {
    echo "File $file should contain: $pattern" >&2
    return 1
  }
}

# Assert environment variable is set
assert_env_set() {
  local var_name="$1"
  [ -n "${!var_name:-}" ] || {
    echo "Environment variable $var_name should be set" >&2
    return 1
  }
}

# Assert environment variable equals value
assert_env_equals() {
  local var_name="$1"
  local expected="$2"
  local actual="${!var_name:-}"
  [ "$actual" == "$expected" ] || {
    echo "Expected $var_name=$expected, got: $actual" >&2
    return 1
  }
}

# Get script directory (same as in actual scripts)
get_script_dir() {
  local source_file="${BASH_SOURCE[0]}"
  cd "$(dirname "$source_file")" && pwd
}

# Create temporary test directory
create_test_dir() {
  mktemp -d "${BATS_TMPDIR}/azure-test.XXXXXX"
}

# Cleanup test directory
cleanup_test_dir() {
  local dir="$1"
  [ -d "$dir" ] && rm -rf "$dir"
}
