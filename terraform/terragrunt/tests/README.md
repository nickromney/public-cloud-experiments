# Makefile Tests

Comprehensive BATS test suite for the Terragrunt Makefile, ensuring command routing, stack mapping, and deployment functionality work correctly.

## Test Structure

```text
tests/
├── README.md                           # This file
├── setup.bash                          # Setup run before each test
├── teardown.bash                       # Cleanup run after each test
├── helpers.bash                        # Helper functions and assertions
├── mocks.bash                          # Mocking functions for commands
├── test_command_routing.bats           # Command routing and stack mapping tests
├── test_infrastructure_lifecycle.bats  # Init, plan, apply, destroy, validate tests
├── test_deployment_commands.bats       # Deploy function-app, frontend tests
├── test_error_handling.bats            # Error handling and edge cases
├── bin/
│   ├── terragrunt*                     # Mock terragrunt command
│   └── az*                             # Mock az command
├── mock-deployment-scripts/
│   ├── build-function-zip.sh*          # Mock function build script
│   └── build-deployment-zip.sh*        # Mock frontend build script
└── fixtures/                           # JSON fixtures for mock responses (if needed)
```

## Prerequisites

### 1. Install BATS

```bash
# macOS
brew install bats-core

# Linux
# See https://bats-core.readthedocs.io/en/stable/installation.html
```

### 2. Initialize Git Submodules

The test suite uses `bats-support` and `bats-assert` as git submodules:

```bash
# From repository root
git submodule update --init --recursive

# Or just for terragrunt tests
cd terraform/terragrunt
git submodule update --init
```

This will clone the test helper libraries into `tests/test_helper/`:

- `bats-support` - Helper functions for BATS tests
- `bats-assert` - Assertion functions for BATS tests

**Note:** These are tracked as submodules to maintain proper version control and easy updates.

## Running Tests

### Run all tests

```bash
cd terraform/terragrunt
bats tests/
```

### Run specific test file

```bash
bats tests/test_command_routing.bats
```

### Run specific test

```bash
bats tests/test_command_routing.bats --filter "react-apim maps to"
```

### Run with verbose output

```bash
bats tests/ --verbose
```

### Run with timing information

```bash
bats tests/ --timing
```

## Test Coverage

### Command Routing Tests (`test_command_routing.bats`)

- **Stack Name Mapping**: Verifies short aliases map to correct directories
  - `react-apim` → `personal-sub/subnet-calc-react-webapp-apim`
  - `react-webapp` → `personal-sub/subnet-calc-react-webapp`
  - `internal-apim` → `personal-sub/subnet-calc-internal-apim`
  - `static-web-apps` → `personal-sub/subnet-calc-static-web-apps`

- **Command Parsing**: Tests hierarchical command structure
  - `make subnet-calc react-apim init`
  - `make subnet-calc react-apim deploy function-app`

- **Verb Routing**: Ensures verbs route to correct internal targets
  - `init` → `_exec-init`
  - `plan` → `_exec-plan`
  - `apply` → `_exec-apply`
  - `deploy` → `_exec-deploy`

- **Argument Suppression**: Verifies extra arguments don't cause errors

### Infrastructure Lifecycle Tests (`test_infrastructure_lifecycle.bats`)

- **Init Command**: Terragrunt init with --upgrade flag
- **Plan Command**: Init + plan sequence
- **Apply Command**: Init + apply with APIM timing warnings
- **Destroy Command**: Terragrunt destroy
- **Validate Command**: Terragrunt validate
- **Clean Command**: Cache removal
- **Unlock Command**: Force unlock with LOCK_ID
- **Environment Variables**: PERSONAL_SUB_REGION propagation
- **Directory Context**: Commands execute in correct directories

### Deployment Commands Tests (`test_deployment_commands.bats`)

- **Deploy Function App**:
  - Calls `build-function-zip.sh`
  - Uses `az functionapp deployment source config-zip`
  - Passes `--build-remote true --timeout 600`
  - Gets function app name from terragrunt output
  - Cleans up zip file after deployment

- **Deploy Frontend**:
  - Calls `build-deployment-zip.sh`
  - Uses `az webapp deploy --type zip`
  - Gets web app name and API URL from terragrunt output
  - Passes API_BASE_URL to build script
  - Cleans up zip file after deployment

- **Deploy All**:
  - Deploys both function app and frontend
  - Shows completion messages

- **Error Handling**:
  - Build script failures
  - Azure CLI command failures
  - Missing components

### Error Handling Tests (`test_error_handling.bats`)

- **Missing Arguments**: Usage messages for incomplete commands
- **Invalid Stacks**: Clear error messages for unknown stacks
- **Command Failures**: Terragrunt and Azure CLI failures propagate
- **Build Failures**: Build script errors stop deployment
- **Missing Parameters**: LOCK_ID and component requirements
- **Environment Variables**: Default values and validation
- **Exit Codes**: Proper status code propagation
- **Color Output**: ANSI color codes in error messages

## Mocking Strategy

### Mock Commands

The test suite uses PATH-based mocking to intercept commands:

1. **`tests/bin/terragrunt`**: Mock terragrunt CLI
   - Tracks all commands and arguments to file
   - Records current directory for each call
   - Returns realistic fixtures
   - Supports failure mode via `MOCK_TERRAGRUNT_FAIL`

2. **`tests/bin/az`**: Mock Azure CLI
   - Tracks all commands to file
   - Returns JSON fixtures
   - Supports failure mode via `MOCK_AZ_FAIL`

3. **Mock Build Scripts**: Simplified versions
   - Track calls to file
   - Create dummy zip files
   - Support failure mode via `MOCK_BUILD_FAIL`

### Mock Control Variables

- `MOCK_TERRAGRUNT_FAIL`: Make terragrunt commands fail
- `MOCK_AZ_FAIL`: Make az commands fail
- `MOCK_BUILD_FAIL`: Make build scripts fail
- `SCRIPTS_DIR`: Override deployment scripts directory

### Assertions

Custom assertions for verifying command execution:

```bash
# Terragrunt assertions
assert_terragrunt_called "init"
assert_terragrunt_arg "--upgrade" ""
assert_terragrunt_called_in_dir "personal-sub/subnet-calc-react-webapp-apim"

# Azure CLI assertions
assert_az_called "functionapp deployment"
assert_az_arg "--resource-group" "rg-test"

# Build script assertions
assert_build_script_called "build-function-zip.sh"

# Call counts
terragrunt_call_count
az_call_count
```

## Test Environment

Each test runs in an isolated environment with:

- Temporary directory: `$BATS_TEST_TMPDIR`
- Mock binaries in PATH
- Required environment variables set:
  - `PERSONAL_SUB_REGION=uksouth`
  - `RESOURCE_GROUP=rg-test`
  - `ARM_SUBSCRIPTION_ID` (mock value)
  - `ARM_TENANT_ID` (mock value)
  - Backend variables for terragrunt

## Writing New Tests

### Test Template

```bash
#!/usr/bin/env bats

setup() {
  load setup
}

teardown() {
  load teardown
}

@test "descriptive test name" {
  # Set required environment
  export SCRIPTS_DIR="${BATS_TEST_DIRNAME}/mock-deployment-scripts"

  # Run command
  run make subnet-calc react-apim <verb>

  # Assert outcome
  assert_success
  assert_output --partial "expected output"

  # Assert commands called
  assert_terragrunt_called "expected-command"
}
```

### Best Practices

1. **Descriptive Names**: Test names should clearly describe what's being tested
2. **Isolated Tests**: Each test should be independent
3. **Mock Control**: Set `SCRIPTS_DIR` to use mock scripts
4. **Cleanup**: Use teardown to clean temporary files
5. **Assertions**: Use specific assertions rather than checking all output
6. **Failure Modes**: Test both success and failure scenarios

## Debugging Tests

### View Mock Command Calls

```bash
# Run test and check tracking files
bats tests/test_command_routing.bats
cat /tmp/terragrunt_calls_*
cat /tmp/az_calls_*
```

### Run Single Test with Debug Output

```bash
bats tests/test_command_routing.bats --filter "react-apim maps" --verbose
```

### Print Mock Calls in Test

Add to your test:

```bash
@test "my test" {
  run make subnet-calc react-apim plan

  # Debug: print all commands called
  print_all_calls

  assert_success
}
```

## Continuous Integration

These tests can run in CI without requiring:

- Azure login
- Actual Azure resources
- Real terragrunt/tofu installation
- Real deployment artifacts

Only requirement: `bats-core` installed

### GitHub Actions Example

```yaml
name: Test Makefile

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive  # Initialize submodules
      - name: Install BATS
        run: |
          sudo apt-get update
          sudo apt-get install -y bats
      - name: Run tests
        run: |
          cd terraform/terragrunt
          bats tests/
```

## Test Statistics

- **Total Test Files**: 4
- **Estimated Test Count**: ~100+ tests
- **Coverage Areas**:
  - Command routing and stack mapping
  - Infrastructure lifecycle (init, plan, apply, destroy, validate)
  - Deployment commands (function-app, frontend, all)
  - Error handling and edge cases
- **Mock Commands**: terragrunt, az, build scripts
- **Pattern Inspired By**: `cloud-networking/azure/tests/`

## Maintenance

### Adding New Stacks

1. Add mapping to `STACK_MAP` in Makefile
2. Add routing test in `test_command_routing.bats`

### Adding New Verbs

1. Implement `_exec-<verb>` target in Makefile
2. Add routing test in `test_command_routing.bats`
3. Add functional tests in appropriate test file

### Updating Mock Responses

Edit mock scripts in `tests/bin/` to return different fixtures.

## Related Documentation

- [BATS Core Documentation](https://bats-core.readthedocs.io/)
- [bats-assert Library](https://github.com/bats-core/bats-assert)
- [bats-support Library](https://github.com/bats-core/bats-support)
- [Parent Project Tests](../../cloud-networking/azure/tests/)
