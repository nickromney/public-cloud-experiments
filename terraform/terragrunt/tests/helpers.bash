#!/usr/bin/env bash
#
# Helper functions and assertions for Makefile BATS tests
#
# Note: $status and $output are provided by BATS's run command
# shellcheck disable=SC2154

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

# Assert file exists
assert_file_exists() {
  local file="$1"
  [ -f "$file" ] || {
    echo "Expected file to exist: $file" >&2
    return 1
  }
}

# Assert file does not exist
assert_file_not_exists() {
  local file="$1"
  [ ! -f "$file" ] || {
    echo "Expected file NOT to exist: $file" >&2
    return 1
  }
}

# Assert file contains pattern
assert_file_contains() {
  local file="$1"
  local pattern="$2"
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

# Create temporary test directory
create_test_dir() {
  mktemp -d "${BATS_TMPDIR}/terragrunt-makefile-test.XXXXXX"
}

# Cleanup test directory
cleanup_test_dir() {
  local dir="$1"
  [ -d "$dir" ] && rm -rf "$dir"
}

# Assert make variable equals expected value
assert_make_var() {
  local var_name="$1"
  local expected="$2"

  run make -C "${BATS_TEST_DIRNAME}/.." --no-print-directory -f - <<EOF
include Makefile
print-%:
	@echo \$(\$*)
EOF

  local actual
  actual=$(make -C "${BATS_TEST_DIRNAME}/.." --no-print-directory print-"$var_name" 2>/dev/null)

  [ "$actual" == "$expected" ] || {
    echo "Expected make variable $var_name=$expected, got: $actual" >&2
    return 1
  }
}

# Run make with dry-run to see what commands would be executed
make_dry_run() {
  make -C "${BATS_TEST_DIRNAME}/.." --dry-run --no-print-directory "$@" 2>&1
}

# Extract colored output codes for testing help display
strip_color_codes() {
  sed 's/\x1b\[[0-9;]*m//g'
}
