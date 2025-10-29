#!/usr/bin/env bats
#
# Tests for Azure CLI query patterns across all scripts
# Validates that scripts use correct query paths for Azure resources
#
# Common bugs we're preventing:
# - Using "properties.defaultHostName" instead of "defaultHostName"
# - Using "properties.customDomainVerificationId" instead of "customDomainVerificationId"

setup() {
  load setup
}

teardown() {
  load teardown
}

# === Function App Hostname Query Tests ===

@test "Scripts must not use properties.defaultHostName (incorrect pattern)" {
  # This pattern is BROKEN and returns empty values
  # Find any scripts using it
  run bash -c "grep -r 'properties\\.defaultHostName' *.sh 2>/dev/null || true"

  # Should have no matches (exit code 1 from grep means no matches, which is what we want)
  if [[ -n "${output}" ]]; then
    echo "Found scripts using broken pattern 'properties.defaultHostName':"
    echo "${output}"
    echo ""
    echo "These scripts should use 'defaultHostName' instead (without properties. prefix)"
    return 1
  fi
}

@test "Deployment scripts use correct defaultHostName query pattern" {
  # Check key deployment scripts use the correct pattern
  for script in 10-function-app.sh 13-create-function-app-on-app-service-plan.sh \
                21-deploy-function.sh 22-deploy-function-zip.sh; do
    if [[ -f "${script}" ]]; then
      # Check script contains at least one correct query
      run grep -E 'query.*"defaultHostName"' "${script}"
      if [[ "${status}" -ne 0 ]]; then
        echo "Script ${script} doesn't contain correct 'defaultHostName' query pattern"
        return 1
      fi
    fi
  done
}

@test "Stack scripts use correct defaultHostName query pattern" {
  # Check stack deployment scripts
  for script in azure-stack-14-swa-noauth-jwt.sh azure-stack-15-swa-entraid-linked.sh; do
    if [[ -f "${script}" ]]; then
      run grep -E 'query.*"defaultHostName"' "${script}"
      if [[ "${status}" -ne 0 ]]; then
        echo "Script ${script} doesn't contain correct 'defaultHostName' query pattern"
        return 1
      fi
    fi
  done
}

# === Custom Domain Verification ID Query Tests ===

@test "Scripts must not use properties.customDomainVerificationId (incorrect pattern)" {
  # This pattern is BROKEN and returns empty values
  run bash -c "grep -r 'properties\\.customDomainVerificationId' *.sh 2>/dev/null || true"

  if [[ -n "${output}" ]]; then
    echo "Found scripts using broken pattern 'properties.customDomainVerificationId':"
    echo "${output}"
    echo ""
    echo "These scripts should use 'customDomainVerificationId' instead (without properties. prefix)"
    return 1
  fi
}

@test "Stack scripts use correct customDomainVerificationId query pattern" {
  # Check scripts that configure custom domains
  for script in azure-stack-14-swa-noauth-jwt.sh azure-stack-15-swa-entraid-linked.sh; do
    if [[ -f "${script}" ]]; then
      # Only test if script actually uses this query
      if grep -q "customDomainVerificationId" "${script}"; then
        run grep -E 'query.*"customDomainVerificationId"' "${script}"
        if [[ "${status}" -ne 0 ]]; then
          echo "Script ${script} doesn't contain correct 'customDomainVerificationId' query pattern"
          return 1
        fi

        # Also verify it doesn't use the broken pattern
        run bash -c "grep 'properties\\.customDomainVerificationId' '${script}' 2>/dev/null || true"
        if [[ -n "${output}" ]]; then
          echo "Script ${script} uses BROKEN 'properties.customDomainVerificationId' pattern"
          return 1
        fi
      fi
    fi
  done
}

# === VNet Integration Query Tests ===

@test "14-configure-function-vnet-integration.sh uses subnet resource ID" {
  # This script should pass full subnet ID, not just names
  # Check that it gets the subnet ID (query is on separate line, so check both parts)
  run grep 'SUBNET_ID.*az network vnet subnet show' 14-configure-function-vnet-integration.sh
  assert_success

  run grep 'query "id"' 14-configure-function-vnet-integration.sh
  assert_success

  # Check that it uses the subnet ID variable (not name)
  run grep -- '--subnet "${SUBNET_ID}"' 14-configure-function-vnet-integration.sh
  assert_success
}

@test "14-configure-function-vnet-integration.sh extracts VNet name from resource ID correctly" {
  # Should use awk to extract virtualNetworks name from path
  run grep -E 'virtualNetworks.*print' 14-configure-function-vnet-integration.sh
  assert_success
}

@test "14-configure-function-vnet-integration.sh extracts Subnet name from resource ID correctly" {
  # Should use awk to extract subnets name from path
  run grep -E 'subnets.*print' 14-configure-function-vnet-integration.sh
  assert_success
}

# === Query Pattern Documentation Tests ===

@test "Scripts document what queries they use" {
  # Important scripts should have comments explaining query patterns
  for script in 10-function-app.sh 13-create-function-app-on-app-service-plan.sh; do
    if [[ -f "${script}" ]]; then
      # Check for hostname-related comments or documentation
      run grep -E '#.*hostname|#.*URL|Get.*hostname' "${script}"
      assert_success
    fi
  done
}

# === Consistency Tests ===

@test "All scripts use consistent defaultHostName query pattern" {
  # Find all scripts that query defaultHostName
  SCRIPTS_WITH_QUERY=$(grep -l 'defaultHostName' *.sh 2>/dev/null || true)

  if [[ -z "${SCRIPTS_WITH_QUERY}" ]]; then
    skip "No scripts found with defaultHostName queries"
  fi

  # Check each one uses the correct pattern (without properties. prefix)
  for script in ${SCRIPTS_WITH_QUERY}; do
    # Skip if it's just in a comment or documentation
    ACTIVE_QUERIES=$(grep -v '^[[:space:]]*#' "${script}" | grep 'defaultHostName' || true)

    if [[ -n "${ACTIVE_QUERIES}" ]]; then
      # Check it doesn't use broken pattern
      BROKEN=$(echo "${ACTIVE_QUERIES}" | grep 'properties\.defaultHostName' || true)
      if [[ -n "${BROKEN}" ]]; then
        echo "Script ${script} uses broken 'properties.defaultHostName' pattern"
        echo "Found in: ${BROKEN}"
        return 1
      fi
    fi
  done
}

# === Integration Test Helpers ===

@test "Test query patterns can be validated with real Azure CLI (documentation)" {
  # This is a documentation test - shows how to validate queries work
  skip "Documentation test - manual validation steps:

To validate query patterns work with real Azure resources:

1. Create a test Function App:
   az functionapp create --name test-func --resource-group test-rg ...

2. Test correct pattern:
   az functionapp show --name test-func --resource-group test-rg \\
     --query 'defaultHostName' -o tsv
   # Should return: test-func.azurewebsites.net

3. Test broken pattern:
   az functionapp show --name test-func --resource-group test-rg \\
     --query 'properties.defaultHostName' -o tsv
   # Should return: (empty)

4. Same for customDomainVerificationId:
   az functionapp show --name test-func --resource-group test-rg \\
     --query 'customDomainVerificationId' -o tsv
   # Should return: <hex-string>

   az functionapp show --name test-func --resource-group test-rg \\
     --query 'properties.customDomainVerificationId' -o tsv
   # Should return: (empty)
"
}
