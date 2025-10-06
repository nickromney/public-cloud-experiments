# Azure Networking Scripts - Testing Documentation

## Overview

This directory contains comprehensive BATS (Bash Automated Testing System) tests for all Azure networking scripts. Tests run without requiring Azure login by using mocked Azure CLI responses.

## Test Structure

### Test Files

1. **test_validation.bats** (20 tests)
   - Script quality: executability, shebang, set -e, parameters
   - Best practices: readonly variables, comments, output suppression

2. **test_resource_scripts.bats** (14 tests)
   - Resource script command construction
   - Default values and parameter handling

3. **test_orchestrator_scripts.bats** (15 tests)
   - Environment variable handling
   - Script composition and orchestration

4. **test_command_construction.bats** (28 tests)
   - Detailed Azure CLI command building
   - Query syntax validation
   - Output format specifications

5. **test_error_handling.bats** (34 tests)
   - Parameter validation
   - Error messages and exit codes
   - Edge cases and error scenarios
   - ResourceNotFound for all resource types

## Azure CLI Error Responses (from live testing)

### Resource Not Found

**Exit Code:** `3`

**Error Format:**

```text
ERROR: (ResourceNotFound) The Resource 'Microsoft.Network/virtualNetworks/test-vnet' under resource group 'test-rg' was not found.
Code: ResourceNotFound
Message: The Resource 'Microsoft.Network/virtualNetworks/test-vnet' under resource group 'test-rg' was not found.
```

**Tested Resources:**

- Virtual Networks: `az network vnet show`
- Subnets: `az network vnet subnet show`
- Resource Groups: `az group show`
- Container Instances: `az container show`
- Virtual Machines: `az vm show`
- Network Security Groups: `az network nsg show`
- Route Tables: `az network route-table show`
- Public IP Addresses: `az network public-ip show`

### Not Logged In

**Exit Code:** `1`

**Error Format:**

```text
ERROR: Please run 'az login' to setup account.
```

## Mock Architecture

### PATH-based Mocking

The mock system uses a script in `tests/bin/az` that takes precedence over the real Azure CLI via PATH manipulation.

**Key Features:**

- Cross-process command tracking via file (`$AZ_CALLS_FILE`)
- Realistic error responses (exit codes and messages)
- Fixture-based responses for realistic JSON structures

### Fixtures

Located in `tests/fixtures/`:

- `account-show.json` - Azure subscription info
- `container-show.json` - Container instance with IP
- `vm-show.json` - Virtual machine with private IP
- `vnet-show.json` - Virtual network configuration
- `subnet-show.json` - Subnet with address prefix
- `nsg-show.json` - Network security group
- `group-show.json` - Resource group metadata

## Running Tests

```bash
# Unit tests (no Azure required)
make test
make test-unit

# Verbose output
make test-verbose

# Specific test file
make test-file FILE=test_validation

# Watch mode (requires entr)
make test-watch

# Integration tests (requires Azure login)
make test-integration

# Quality checks (lint + test)
make quality
```

## Environment Variables for Mocking

- `AZ_MOCK_NOT_LOGGED_IN=true` - Simulate not being logged in
- `AZ_MOCK_RESOURCE_NOT_FOUND=true` - Simulate resource not found (exit 3)
- `AZ_CALLS_FILE` - File path for tracking az commands across processes
- `BATS_TEST_DIRNAME` - Directory containing test files and fixtures

## Test Coverage

**Total:** 111 tests

- Script validation and best practices
- Command construction and defaults
- Error handling and validation
- Realistic Azure error responses
- Query syntax verification
- Output format checking

## Constraints Testing

The scripts are designed to work in constrained environments (like Pluralsight sandboxes) where:

- Cannot create new resource groups
- Limited to specific regions
- Limited role permissions

This ensures scripts will work in both sandbox and full Contributor/Owner scenarios.

## Adding New Tests

1. **Test Azure CLI behavior** in a live environment first
2. **Document exit codes** and error message formats
3. **Update mock script** (`tests/bin/az`) with realistic responses
4. **Add fixtures** if new resource types are involved
5. **Write BATS test** following existing patterns
6. **Run tests** to verify: `make test-unit`

## Known Limitations

- Mocks simulate command-line behavior but not actual Azure resource creation
- Query syntax is verified but not executed against real JSON structures
- Timing and async Azure operations are not tested
- Network connectivity between resources must be tested manually

For integration testing with real Azure resources, use `make test-integration`.
