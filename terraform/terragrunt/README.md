# Terragrunt Experiments

Learning Terragrunt with practical Azure deployments using map-based (0 to n) patterns.

## Structure

```text
terragrunt/
├── root.hcl                          # Root config (backend, providers)
├── setup-env.sh                      # Interactive setup script
├── Makefile                          # Common commands
├── .envrc.example                    # For direnv users
├── ps-az-sbx/app-a/                # Pluralsight sandbox deployment
│   ├── terragrunt.hcl                # Stack config
│   ├── terraform.tfvars              # Your configuration (git-ignored)
│   ├── terraform.tfvars.example      # Toggle pattern examples
│   └── README.md                     # Detailed documentation
└── modules/ps-az-sbx-app/          # Terraform module
    ├── main.tf                       # All resources with for_each
    ├── variables.tf                  # Map-based variables
    └── outputs.tf                    # Map-based outputs
```

## Quick Start

### 1. Setup Environment

Run the interactive setup script:

```bash
./setup-env.sh
```

This will:

- Check Azure CLI is installed and logged in
- Get your Azure subscription and tenant IDs
- Prompt for backend storage account details
- Print export commands for you to run

Then copy/paste the export commands it prints, or manually export variables:

```bash
export ARM_SUBSCRIPTION_ID="your-sub-id"
export ARM_TENANT_ID="your-tenant-id"
export TF_BACKEND_RG="your-backend-rg"
export TF_BACKEND_SA="your-backend-sa"
export TF_BACKEND_CONTAINER="terraform-states"
```

### 2. Configure Your Stack

```bash
cd ps-az-sbx/app-a
cp terraform.tfvars.example terraform.tfvars
```

Update `terraform.tfvars` with your Pluralsight sandbox resource group name.

### 3. Deploy

Using Makefile (from repo root):

```bash
make app-a-init    # Initialize
make app-a-plan    # Plan
make app-a-apply   # Apply
```

Or using Terragrunt directly:

```bash
cd ps-az-sbx/app-a
terragrunt init
terragrunt plan
terragrunt apply
```

## Secure App Stack (App Service + APIM + Function)

The `workloads/secure-app/envs/dev/uksouth` stack deploys the hardened App Service → APIM (Internal) → Function App architecture discussed in the design notes. You can work with it using the dedicated Makefile targets:

```bash
make secure-app-plan      # init + plan
make secure-app-apply     # init + apply
make secure-app-destroy   # destroy the stack
make secure-app-output    # show stack outputs
```

Or run Terragrunt manually:

```bash
cd workloads/secure-app/envs/dev/uksouth
terragrunt init
terragrunt plan
```

## Key Concepts

### Map Pattern (0 to n)

All resources use **maps** instead of booleans:

```hcl
# Disabled - empty map
function_apps = {}

# Enabled - add to map
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "dotnet-isolated"
    runtime_version      = "8.0"
  }
}

# Multiple - add more items (0 to n)
function_apps = {
  "api" = { ... }
  "worker" = { ... }
  "processor" = { ... }
}
```

### Reference Keys

Resources link via keys in maps:

```hcl
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"  # Links to app_service_plans["consumption"]
    storage_account_key  = "funcapp"      # Links to storage_accounts["funcapp"]
  }
}
```

## Available Resources

All resources are toggleable via maps:

- **Storage Accounts** - For Function Apps
- **App Service Plans** - Consumption or dedicated
- **Function Apps** - .NET, Python, Node.js
- **Static Web Apps** - Frontend hosting
- **API Management** - Developer tier
- **APIM APIs** - Link Functions to APIM

## Makefile Commands

```bash
make help              # Show all commands
make setup             # Run setup script
make check-env         # Check environment variables

make app-a-init        # Initialize app-a
make app-a-plan        # Plan app-a
make app-a-apply       # Apply app-a
make app-a-destroy     # Destroy app-a
make app-a-output      # Show outputs
make app-a-clean       # Clean cached files

make fmt               # Format Terraform files
make validate          # Validate configurations
make clean             # Clean all cached files
```

## Examples

See `ps-az-sbx/app-a/terraform.tfvars.example` for:

1. **Just Function App** - Minimal backend
2. **Full Stack** - Functions + SWA + APIM
3. **Multiple Function Apps** - 0 to n pattern
4. **Just Static Web App** - Frontend only

## For Direnv Users

```bash
cp .envrc.example .envrc
# Edit .envrc with your values
direnv allow
```

If you prefer not to use `direnv`, export the variables manually in your shell (or place them in your shell profile):

```bash
export ARM_SUBSCRIPTION_ID="your-sub-id"
export ARM_TENANT_ID="your-tenant-id"
export TF_BACKEND_RG="your-backend-rg"
export TF_BACKEND_SA="your-backend-sa"
export TF_BACKEND_CONTAINER="terraform-states"
```

NuShell equivalent (`~/.config/nushell/env.nu`):

```nushell
let-env ARM_SUBSCRIPTION_ID "your-sub-id"
let-env ARM_TENANT_ID "your-tenant-id"
let-env TF_BACKEND_RG "your-backend-rg"
let-env TF_BACKEND_SA "your-backend-sa"
let-env TF_BACKEND_CONTAINER "terraform-states"
```

## Testing Early

Always test with minimal config first:

```hcl
# terraform.tfvars - minimal test
existing_resource_group_name = "your-sandbox-rg"

storage_accounts = {
  "test" = {
    account_tier      = "Standard"
    replication_type  = "LRS"
    purpose           = "testing"
  }
}

# Everything else disabled
app_service_plans = {}
function_apps     = {}
static_web_apps   = {}
apim_instances    = {}
apim_apis         = {}
```

Then gradually enable more resources.

## Pluralsight Sandbox Notes

- **4-hour expiration** - Everything is ephemeral
- **Vended resource group** - Cannot create new RGs
- **Limited regions** - eastus, westus2
- **No role assignments** - Sandbox limitation

## Troubleshooting

### Environment variables not set

Run `make check-env` to see which variables are missing.

### Backend storage not found

Run `./setup-env.sh` to create or configure backend storage.

### Module not found

Make sure you're running commands from the correct directory:

- Makefile commands: From `terragrunt/` root
- Terragrunt commands: From `ps-az-sbx/app-a/`
