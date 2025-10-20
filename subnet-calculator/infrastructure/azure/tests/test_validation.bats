#!/usr/bin/env bats
#
# Tests for script validation requirements
# Ensures all scripts follow security and quality standards

setup() {
  load setup
}

teardown() {
  load teardown
}

# Shebang validation tests
@test "00-static-web-app.sh has shebang" {
  assert_has_shebang "00-static-web-app.sh"
}

@test "10-function-app.sh has shebang" {
  assert_has_shebang "10-function-app.sh"
}

@test "20-deploy-frontend.sh has shebang" {
  assert_has_shebang "20-deploy-frontend.sh"
}

@test "42-configure-entraid-swa.sh has shebang" {
  assert_has_shebang "42-configure-entraid-swa.sh"
}

# Executable permission tests
@test "00-static-web-app.sh is executable" {
  assert_executable "00-static-web-app.sh"
}

@test "10-function-app.sh is executable" {
  assert_executable "10-function-app.sh"
}

@test "20-deploy-frontend.sh is executable" {
  assert_executable "20-deploy-frontend.sh"
}

@test "42-configure-entraid-swa.sh is executable" {
  assert_executable "42-configure-entraid-swa.sh"
}

# Error handling tests
@test "00-static-web-app.sh has set -euo pipefail" {
  assert_has_set_errexit "00-static-web-app.sh"
}

@test "10-function-app.sh has set -euo pipefail" {
  assert_has_set_errexit "10-function-app.sh"
}

@test "20-deploy-frontend.sh has set -euo pipefail" {
  assert_has_set_errexit "20-deploy-frontend.sh"
}

@test "42-configure-entraid-swa.sh has set -euo pipefail" {
  assert_has_set_errexit "42-configure-entraid-swa.sh"
}

# Log function tests - These would have caught the missing log_step issue
@test "20-deploy-frontend.sh defines log_info function" {
  run grep -q "^log_info()" "20-deploy-frontend.sh"
  assert_success
}

@test "20-deploy-frontend.sh defines log_error function" {
  run grep -q "^log_error()" "20-deploy-frontend.sh"
  assert_success
}

@test "20-deploy-frontend.sh defines log_step function" {
  run grep -q "^log_step()" "20-deploy-frontend.sh"
  assert_success
}

@test "20-deploy-frontend.sh defines log_warn function" {
  run grep -q "^log_warn()" "20-deploy-frontend.sh"
  assert_success
}

@test "42-configure-entraid-swa.sh defines log_info function" {
  run grep -q "^log_info()" "42-configure-entraid-swa.sh"
  assert_success
}

@test "42-configure-entraid-swa.sh defines log_error function" {
  run grep -q "^log_error()" "42-configure-entraid-swa.sh"
  assert_success
}

@test "42-configure-entraid-swa.sh defines log_step function" {
  run grep -q "^log_step()" "42-configure-entraid-swa.sh"
  assert_success
}

@test "42-configure-entraid-swa.sh defines log_warn function" {
  run grep -q "^log_warn()" "42-configure-entraid-swa.sh"
  assert_success
}
