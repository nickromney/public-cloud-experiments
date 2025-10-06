# Azure Networking Scripts

Hands-on Azure networking experiments with automated testing.

## Overview

This directory contains shell scripts for deploying Azure networking resources, designed to work in constrained environments like Pluralsight sandboxes. All scripts are thoroughly tested with BATS (Bash Automated Testing System).

## Quick Start

### 1. Setup Environment

```bash
# Automatically detect resource group and configure environment
make setup

# Or run directly
./setup-env.sh
```

The setup script will:

- Check Azure CLI login status
- Auto-detect resource group (perfect for Pluralsight sandboxes)
- Provide export command for `RESOURCE_GROUP`

### 2. Export Environment Variable

```bash
# Copy the export command from setup output
export RESOURCE_GROUP='your-resource-group-name'
```

### 3. Run Scripts

```bash
# Deploy simple network (VNET + subnets + NSG)
./02-azure-simple-network.sh

# Deploy network with container instance
./03-azure-network-aci.sh

# See all available scripts
ls -1 *.sh
```

## Environment Detection

The `setup-env.sh` script intelligently detects your Azure environment:

- **Single Resource Group** (Pluralsight sandbox): Auto-selects the only available RG
- **Multiple Resource Groups**: Prompts you to choose
- **No Resource Groups**: Provides guidance on creating one

This pattern ensures scripts work in:

- Pluralsight sandboxes (limited permissions, single RG)
- Full Azure subscriptions (Contributor/Owner roles)

## Testing

### Unit Tests (No Azure Required)

```bash
# Run all tests with mocked Azure CLI
make test

# Run with verbose output
make test-verbose

# Watch mode (requires entr)
make test-watch
```

### Integration Tests (Requires Azure Login)

```bash
# Run tests against real Azure
make test-integration
```

### Test Coverage

- **111 total tests** across 5 test files
- Validates command construction, error handling, best practices
- Uses realistic Azure CLI mocks based on live testing
- See [tests/TESTING.md](tests/TESTING.md) for details

## Scripts

### Resource Scripts (Low-level)

- `resource-vnet.sh` - Create virtual network
- `resource-subnet.sh` - Create subnet with NSG and delegation support
- `resource-nsg.sh` - Create network security group
- `resource-nsg-rule.sh` - Create/delete NSG rules
- `resource-route-table.sh` - Create route table
- `resource-route.sh` - Create route
- `resource-container-instance.sh` - Deploy container instance
- `resource-container-custom.sh` - Deploy container with custom content
- `resource-virtual-machine.sh` - Deploy virtual machine

### Orchestrator Scripts (High-level)

- `02-azure-simple-network.sh` - Simple network topology
- `03-azure-network-aci.sh` - Network with container instance
- `06-container-tests.sh` - Test container connectivity
- `07-vm.sh` - Deploy VM with cloud-init
- `09-custom-containers.sh` - Deploy custom containers
- `10-nsg-demo.sh` - Interactive NSG demonstration
- `11-nsg-test.sh` - Automated NSG testing
- `12-private-vm.sh` - Deploy private VM (no public IP)
- `13-private-vm-tests.sh` - Test private VM connectivity
- `14-nva-routing.sh` - Network Virtual Appliance with routing
- `15-nva-tests.sh` - Test NVA routing

## Quality Assurance

### Local Checks

```bash
# Run shellcheck + unit tests
make quality

# Run shellcheck only
make lint
```

### Pre-commit Hooks (Repo Root)

```bash
cd ../..
make precommit
```

Runs:

- Gitleaks (secret scanning)
- Shellcheck (shell script linting)
- Markdownlint (documentation)
- Trailing whitespace/EOF fixes

## Design Patterns

### Environment Variables

Scripts use environment variables with sensible defaults:

```bash
# Required (set by setup-env.sh)
RESOURCE_GROUP="your-rg-name"

# Optional (auto-detected or defaulted)
LOCATION="$(az group show --name $RESOURCE_GROUP --query location -o tsv)"
VNET_PREFIX="10.0.0.0/16"
```

### Error Handling

All scripts use:

- `set -euo pipefail` - Exit on errors, undefined variables
- Parameter validation with helpful error messages
- Readonly variables for constants

### Azure CLI Patterns

- `--output none` for create operations (suppress JSON)
- `--query` with JMESPath for extracting values
- `--only-show-errors` to reduce noise

## Constrained Environments

These scripts are designed for environments with limited permissions:

- Works with vended resource groups (Pluralsight sandboxes)
- No assumption of Contributor/Owner roles
- Auto-detects location from resource group
- Handles pre-existing resources gracefully

If scripts work in a sandbox, they'll work with full permissions.

## Documentation

- [TESTING.md](tests/TESTING.md) - Comprehensive testing documentation
- [Mock Architecture](tests/bin/az) - Azure CLI mocking for tests
- [Test Fixtures](tests/fixtures/) - Realistic Azure response samples

## Requirements

- Azure CLI (`brew install azure-cli`)
- BATS for testing (`make install-bats`)
- Bash 4.0+
- Active Azure subscription

## Next Steps

1. Run `make setup` to configure your environment
2. Export the `RESOURCE_GROUP` variable
3. Run `make test` to verify everything works
4. Start deploying with `./02-azure-simple-network.sh`

For questions or issues, see the [main repository README](../../README.md).
