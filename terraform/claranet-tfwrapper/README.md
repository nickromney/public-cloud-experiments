# Claranet TFWrapper Setup

This directory contains a Terraform project configured according to Claranet's tfwrapper conventions, using their Azure modules with enhanced patterns for maximum flexibility.

## Key Features

- **For-each pattern everywhere** - No count-based resources to avoid state reshuffling
- **Flexible resource management** - Support for both creating new and referencing existing resources
- **Consistent ID-based references** - All existing resources referenced by full Azure resource IDs
- **Automatic quality checks** - Format and lint before plan/apply operations
- **Landing zone ready** - Perfect for both greenfield and vended subscription scenarios

## Structure

Following tfwrapper's opinionated directory structure:

```text
├── Makefile                                        # Simplified commands with quality checks
├── .tflint.hcl                                    # TFLint configuration with azurerm plugin v0.29.0
├── conf/                                           # Stack configurations
│   ├── azure-experiments_dev_uksouth_platform.yml # Platform stack config
│   ├── state.yml                                  # State backend configuration (gitignored)
│   └── state.yml.template                         # Template for state.yml
├── templates/                                      # Stack templates
│   └── azure/
│       ├── common/
│       │   └── state.tf.jinja2                    # Backend state template
│       ├── basic/                                 # Basic stack template
│       │   ├── main.tf                            # Basic Claranet modules
│       │   ├── provider.tf
│       │   ├── variables.tf
│       │   ├── versions.tf                        # Using .tf not .tofu for tflint compatibility
│       │   └── outputs.tf
│       └── platform/                              # Platform stack template (enhanced)
│           ├── main.tf                            # Full platform with for_each pattern
│           ├── provider.tf
│           ├── variables.tf                       # Enhanced with existing resource support
│           ├── versions.tf                        # Using .tf not .tofu for tflint compatibility
│           └── outputs.tf                         # Map-based outputs for for_each
├── azure-experiments/                             # Account name
│   └── dev/                                       # Environment
│       └── uksouth/                               # Region
│           └── platform/                          # Stack (bootstrapped)
│               ├── main.tf
│               ├── provider.tf
│               ├── variables.tf
│               ├── terraform.tfvars               # Example configuration
│               ├── versions.tf
│               ├── outputs.tf
│               └── state.tf                       # Generated backend config (gitignored)
├── .run/                                           # Credentials cache
│   └── .gitignore
├── setup-env.sh                                   # Script to set up environment variables
├── generate-state-config.sh                       # Script to generate state.yml from template
├── .gitignore                                     # Ignores state.yml and state.tf files
└── README.md                                       # This file
```

## Enhanced Variable Pattern

### Core Principles

1. **Presence in map means create** - No need for `create = true` flags
2. **Consistent ID references** - All existing resources use full Azure resource IDs
3. **For-each everywhere** - Even for single resources to enable 0 to N flexibility

### Example: Greenfield Deployment

```hcl
# Create everything new
resource_groups = {
  "platform" = {}
}

storage_accounts = {
  "logs" = {
    resource_group_key = "platform"  # Reference the RG we're creating
    purpose           = "logs"
  }
}

function_apps = {
  "api" = {
    resource_group_key  = "platform"
    storage_account_key = "logs"  # Reference the storage we're creating
    runtime_stack       = "python"
  }
}
```

### Example: Landing Zone Deployment

```hcl
# Reference existing resources by ID
existing_resource_groups = {
  "platform" = "/subscriptions/xxx/resourceGroups/rg-platform-lz-001"
}

existing_log_analytics_workspaces = {
  "shared" = "/subscriptions/xxx/resourceGroups/rg-shared/providers/Microsoft.OperationalInsights/workspaces/log-shared-001"
}

# Create new resources in existing RG
storage_accounts = {
  "app" = {
    existing_resource_group_id = "/subscriptions/xxx/resourceGroups/rg-platform-lz-001"
    purpose                    = "application"
  }
}

function_apps = {
  "api" = {
    existing_resource_group_id  = "/subscriptions/xxx/resourceGroups/rg-platform-lz-001"
    existing_storage_account_id = "/subscriptions/xxx/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stapp001"
    existing_log_analytics_id   = "/subscriptions/xxx/resourceGroups/rg-shared/providers/Microsoft.OperationalInsights/workspaces/log-shared-001"
    runtime_stack               = "python"
  }
}
```

## Components Configured

Using Claranet's Azure modules (all at version ~8.x):

1. **Azure Region Module** (`claranet/regions/azurerm`)
   - Sets up region configuration

2. **Resource Group Module** (`claranet/rg/azurerm`)
   - Creates resource groups with standardized naming
   - Supports existing RG references via data sources

3. **Run Module** (`claranet/run/azurerm`)
   - Sets up logging and monitoring infrastructure
   - Log Analytics Workspace with configurable retention

4. **Storage Account Module** (`claranet/storage-account/azurerm`)
   - Creates storage accounts with advanced features
   - Blob versioning, soft delete, change feed

5. **App Service Plan Module** (`claranet/app-service-plan/azurerm`)
   - Creates App Service Plans with flexible SKUs

6. **Function App Module** (`claranet/function-app/azurerm`)
   - Creates Function Apps with runtime configuration
   - Integrated Application Insights support

7. **Key Vault Module** (`claranet/keyvault/azurerm`)
   - Creates Key Vaults with soft delete and purge protection

8. **AKS Support** (native azurerm)
   - AKS cluster creation with managed identity

## Prerequisites

1. Install tfwrapper using uv:

   ```bash
   uv tool install claranet-tfwrapper
   ```

2. Install tflint and Azure plugin:

   ```bash
   brew install tflint
   tflint --init  # Installs azurerm plugin v0.29.0 as configured
   ```

3. Set up Azure environment:

   ```bash
   # Source the setup script to configure environment variables
   source ./setup-env.sh

   # This will:
   # - Check Azure CLI login status
   # - Get current subscription and tenant IDs
   # - Prompt for backend storage details (or use existing env vars)
   # - Export all required environment variables
   ```

4. Generate state configuration from environment:

   ```bash
   # Generate conf/state.yml from template using environment variables
   ./generate-state-config.sh

   # This creates conf/state.yml with your actual Azure values
   # The generated file should NOT be committed to version control
   ```

## Makefile Usage (Preferred)

A comprehensive Makefile is provided to simplify tfwrapper operations. All commands include automatic quality checks (formatting and linting) before plan/apply operations.

### Quick Start

```bash
# Show all available commands
make help

# Run a plan for the platform stack
make platform plan dev uks

# Apply changes
make platform apply dev uks

# Initialize a stack
make platform init dev uks
```

### Available Targets

#### Stack Operations

```bash
# Format: make <stack> <action> <env> <region>
make platform plan dev uks      # Plan platform stack in dev/uksouth
make platform apply dev uks     # Apply platform stack in dev/uksouth
make basic init uat ukw        # Initialize basic stack in uat/ukwest
make platform bootstrap dev uks # Bootstrap new platform stack

# Actions: bootstrap, init, plan, apply, destroy, output, refresh
# Environments: dev, uat, prod
# Regions: uks (uksouth), ukw (ukwest), eun (northeurope),
#          euw (westeurope), use (eastus), usw (westus)
```

#### Quality Commands

```bash
make fmt                        # Format all Terraform files
make fmt-check                  # Check if files are formatted (CI-friendly)
make lint                       # Run tflint on all local code (excludes downloaded modules)
make quality                    # Run all quality checks (fmt-check + lint)
make validate STACK=platform ENV=dev REGION=uks  # Validate specific stack
```

#### Other Commands

```bash
make list                       # List configured and deployed stacks
make clean                      # Remove .terraform directories and lock files
make setup                      # Initial Azure setup (login check, state config)
make generate-stack-config STACK=platform ENV=dev REGION=uks  # Generate stack config
```

#### State Lock Management

```bash
# When you encounter a state lock error, the error message will show a Lock ID like:
# Lock Info:
#   ID: 44b9bad3-9571-3ff3-77e3-019f0b238f1a
#   Path: terraform-states/experiments/azure-experiments/dev/uksouth/platform/terraform.state

# Try auto-detect first (may not always work)
make unlock STACK=platform ENV=dev REGION=uks

# If auto-detect fails, use the specific Lock ID from the error message
make unlock STACK=platform ENV=dev REGION=uks LOCK_ID=44b9bad3-9571-3ff3-77e3-019f0b238f1a
```

### Automatic Quality Checks

The Makefile automatically runs quality checks before `plan` and `apply` operations:

1. **Formatting**: Runs `terraform fmt` (or `tofu fmt`) to ensure consistent code style
2. **Linting**: Runs `tflint` with the azurerm plugin (v0.29.0) to catch potential issues

These checks help maintain code quality and catch issues early.

### Notes on File Extensions

- **versions.tf vs versions.tofu**: We use `versions.tf` instead of `versions.tofu` for tflint compatibility. While OpenTofu supports `.tofu` extensions, tflint currently only processes `.tf` files by default, so we stick with `.tf` for better tooling support.

## Manual tfwrapper Usage

### Bootstrap the Stack

**Important**: Before bootstrapping, you must create a configuration file in `conf/` with the naming pattern:
`{account}_{environment}_{region}_{stack}.yml`

Stack naming should represent the logical purpose, not specific resources:

- Good: `platform`, `api`, `web`, `data`, `core`
- Avoid: `app-service`, `function-app`, `storage-account`

From the project root:

```bash
# Bootstrap using the azure/platform template (enhanced with for_each)
tfwrapper -a azure-experiments -e dev -r uksouth -s platform bootstrap azure/platform

# Bootstrap using the azure/basic template
tfwrapper -a azure-experiments -e dev -r uksouth -s api bootstrap azure/basic

# For a different region, first create the config file, then:
tfwrapper -a azure-experiments -e dev -r ukwest -s platform bootstrap azure/platform
```

### Working with the Stack

```bash
# From the project root
tfwrapper -a azure-experiments -e dev -r uksouth -s platform init
tfwrapper -a azure-experiments -e dev -r uksouth -s platform plan
tfwrapper -a azure-experiments -e dev -r uksouth -s platform apply

# Or from the stack directory
cd azure-experiments/dev/uksouth/platform
tfwrapper init
tfwrapper plan
tfwrapper apply
```

## Configuration Details

### Stack Configuration

The stack configuration (`conf/azure-experiments_dev_uksouth_platform.yml`) uses:

- Azure AD authentication (`mode: user`)
- OpenTofu 1.10.5
- Azure backend with storage account keys (`use_azuread_auth: false`)

### State Backend Configuration

The state backend (`conf/state.yml`) defines:

- Azure blob storage backend
- Option for Azure AD auth or storage account keys
- Storage account and resource group for backend location
- Container name: `terraform-states` (hardcoded in state.tf.jinja2)

**Important**: If using Azure AD auth, ensure you have the "Storage Blob Data Owner" role on the storage account.

### Diagnostic Settings

The templates include a `local.enable_diagnostics` flag (default: `false`) to avoid circular dependencies during initial deployment. Set this to `true` after the infrastructure exists to enable diagnostic logging.

## Known Issues and Troubleshooting

### State Lock Issues

If you encounter a state lock error during `plan` or `apply`:

```text
Error: Error acquiring the state lock
Lock Info:
  ID:        44b9bad3-9571-3ff3-77e3-019f0b238f1a
  Path:      terraform-states/experiments/azure-experiments/dev/uksouth/platform/terraform.state
```

Use the `make unlock` command with the Lock ID shown in the error:

```bash
make unlock STACK=platform ENV=dev REGION=uks LOCK_ID=44b9bad3-9571-3ff3-77e3-019f0b238f1a
```

This can happen when:

- A previous operation was interrupted (Ctrl+C)
- Network issues caused a disconnection
- Multiple users/processes are accessing the same state

### Azure CLI Isolation

tfwrapper uses an isolated Azure CLI configuration in the `.run/azure` directory. This means:

- Your normal `az login` session is not automatically available to tfwrapper
- You may need to login separately for tfwrapper with: `AZURE_CONFIG_DIR=.run/azure az login`
- The tool validates subscription IDs in stack configurations even when using `mode: user`

### OpenTofu Plugin Cache Warning

You may see a warning about plugin cache directory:

```text
Error: The specified plugin cache dir /Users/[username]/.terraform.d/plugin-cache cannot be opened
```

This is just a warning and doesn't affect functionality. To resolve it, create the directory:

```bash
mkdir -p ~/.terraform.d/plugin-cache
```

### Azure Backend Permission Error

If you see:

```text
Error: Failed to get existing workspaces: containers.Client#ListBlobs:
Status=403 Code="AuthorizationPermissionMismatch"
```

When using `use_azuread_auth = true`:

- You need **Storage Blob Data Owner** role (not just Contributor) on the storage container
- Being subscription Owner is not sufficient - you need this specific data plane role
- The role must be assigned at the storage account or container level

To assign the role:

```bash
# Get your user principal ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Storage Blob Data Owner role
az role assignment create \
  --role "Storage Blob Data Owner" \
  --assignee $USER_ID \
  --scope "/subscriptions/xxx/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/stbackend"
```

Alternatively, set `use_azuread_auth = false` to use storage account keys instead.

### Linting Warnings

You may see warnings about unused variables like `existing_app_service_plans`. These are intentionally included in the template to demonstrate the pattern for referencing existing resources and can be safely ignored.

## Resources Created

When applied with the default terraform.tfvars, this will create:

- Resource Group: `rg-platform-experiments-uks-dev`
- Log Analytics Workspace: `log-shared-experiments-uks-dev`
- Storage Account: `stlogsexperimentsuksdev`
- Key Vault: `kv-platform-experiments`
- App Service Plan: `plan-main-experiments-uks-dev` (P0v3 SKU)
- Function App: `fa-api-experiments-uks-dev` (Python 3.11)

All resources follow Claranet's naming conventions:
`{resource_type_prefix}-{stack}-{client_name}-{location_short}-{environment}`

## Best Practices Applied

1. **For-each over count**: All resources use for_each to avoid state reshuffling when resources are added/removed
2. **Flexible resource references**: Support both creating new resources and referencing existing ones
3. **Consistent ID pattern**: All existing resources referenced by full Azure resource IDs for maximum flexibility
4. **Modular locals**: Local values aggregate both created and existing resources for easy reference
5. **Quality first**: Automatic formatting and linting before operations
6. **Clear separation**: Resources to create are in the main maps, existing resources in `existing_*` variables
7. **Landing zone ready**: Pattern supports both greenfield and vended subscription scenarios
