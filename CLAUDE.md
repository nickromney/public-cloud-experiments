# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a multi-project repository for cloud technology experiments, primarily focused on Azure with some AWS. It contains production-ready applications and Infrastructure as Code (IaC) experiments using different tools and patterns.

## Projects

### 1. Subnet Calculator (`subnet-calculator/`)

A full-stack IPv4/IPv6 subnet calculator with containerized microservices architecture.

**Architecture:**

- **Backend**: FastAPI-based Azure Function App (Python 3.11)
- **Frontend**: Flask web application with Pico CSS (Python 3.11)
- **Deployment**: Docker Compose / Podman Compose

**Quick Start:**

```bash
cd subnet-calculator
docker compose up
# Access frontend at http://localhost:8000
# Access API docs at http://localhost:8080/api/v1/docs
```

**Backend Development:**

```bash
cd subnet-calculator/api-fastapi-azure-function
uv sync --extra dev          # Install dependencies
uv run pytest -v             # Run tests
func start                   # Run locally (port 7071)
./test_endpoints.sh          # Test all endpoints
```

**Frontend Development:**

```bash
cd subnet-calculator/frontend-python-flask
uv sync --extra dev          # Install dependencies
uv run pytest -v             # Run tests
uv run flask run             # Run locally (port 5000)
```

### 2. Terraform with Claranet tfwrapper (`terraform/claranet-tfwrapper/`)

Azure infrastructure using Claranet's tfwrapper tool with enhanced patterns.

**Key Patterns:**

- **For-each everywhere**: No count-based resources to avoid state reshuffling
- **Flexible resource management**: Support for both creating new and referencing existing resources via IDs
- **Landing zone ready**: Works in both greenfield and vended subscription scenarios

**Prerequisites:**

```bash
# Install tools
uv tool install claranet-tfwrapper
brew install tflint
tflint --init

# Setup Azure environment
source ./setup-env.sh
./generate-state-config.sh
```

**Common Commands:**

```bash
cd terraform/claranet-tfwrapper

# Using Makefile (preferred)
make platform plan dev uks    # Plan platform stack in dev/uksouth
make platform apply dev uks   # Apply changes
make fmt                      # Format all files
make lint                     # Run tflint
make quality                  # Run all quality checks

# Manual tfwrapper usage
tfwrapper -a azure-experiments -e dev -r uksouth -s platform init
tfwrapper -a azure-experiments -e dev -r uksouth -s platform plan
tfwrapper -a azure-experiments -e dev -r uksouth -s platform apply
```

**Stack Naming Convention:**
Stack names should represent logical purpose (e.g., `platform`, `api`, `data`), not specific resources (avoid `app-service`, `function-app`).

**Important Notes:**

- Uses OpenTofu 1.10.5
- File extension: `.tf` (not `.tofu`) for tflint compatibility
- State backend: Azure Blob Storage
- `conf/state.yml` is gitignored and must be generated from template

### 3. Terragrunt (`terraform/terragrunt/`)

Azure infrastructure using Terragrunt with map-based (0 to n) patterns.

**Key Pattern - Maps Instead of Booleans:**

```hcl
# Disabled - empty map
function_apps = {}

# Enabled - add to map
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
  }
}

# Multiple instances (0 to n)
function_apps = {
  "api"       = { ... }
  "worker"    = { ... }
  "processor" = { ... }
}
```

**Prerequisites:**

```bash
# Install tools
brew install terragrunt opentofu

# Setup environment
cd terraform/terragrunt
./setup-env.sh
# Then export the variables shown
```

**Common Commands:**

```bash
cd terraform/terragrunt

# Using Makefile (preferred)
make preflight               # Check all prerequisites
make app-a-plan              # Plan ps-az-sbx/app-a
make app-a-apply             # Apply changes
make fmt                     # Format all files

# Direct Terragrunt usage
cd ps-az-sbx/app-a
terragrunt init
terragrunt plan
terragrunt apply
```

**Pluralsight Sandbox Notes:**

- 4-hour expiration - everything is ephemeral
- Cannot create new resource groups (vended RG only)
- Limited regions: eastus, westus2
- No role assignments due to sandbox limitations

## Security and Quality

### Pre-commit Hooks

The repository uses pre-commit hooks for automated quality checks:

**Setup:**

```bash
./setup-security.sh          # Install all tools (macOS)
pre-commit install           # Enable hooks
```

**Manual Execution:**

```bash
pre-commit run --all-files   # Run all hooks
gitleaks detect --verbose    # Secret scanning
```

**Configured Hooks:**

- **Gitleaks**: Secret scanning
- **Terraform**: Format, validate, tflint, tfsec (excludes claranet-tfwrapper/)
- **Shellcheck**: Shell script linting
- **Markdownlint**: Markdown formatting and linting
- **General**: Trailing whitespace, EOF fixer, YAML validation, large files check

### GitHub Actions

- **Secret Scanning**: Runs Gitleaks on push/PR
- **Terraform Security**: Runs tflint and tfsec on Terraform changes

## Development Tools

### Package Management

- **Python**: Uses `uv` for fast, reliable dependency management
- **Terraform**: Uses tfwrapper or terragrunt wrappers

### Required Tools

```bash
# Python (for subnet-calculator)
brew install uv azure-functions-core-tools

# Terraform/OpenTofu
brew install opentofu tflint tfsec
uv tool install claranet-tfwrapper
brew install terragrunt

# Container runtime
brew install docker          # or podman
```

## Common Patterns

### Map-Based Resource Toggles (Terragrunt)

Resources use maps instead of boolean flags. Presence in the map means "create this resource":

```hcl
# Pattern: Empty map = disabled, populated map = enabled
storage_accounts = {
  "logs" = {
    account_tier     = "Standard"
    replication_type = "LRS"
  }
}
```

### For-Each Pattern (tfwrapper)

All resources use `for_each` with maps to enable flexible 0-to-n scaling:

```hcl
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups
  name     = each.value.name
  location = each.value.location
}
```

### Resource References

Resources link via keys in maps:

```hcl
function_apps = {
  "api" = {
    resource_group_key  = "platform"      # Links to resource_groups["platform"]
    storage_account_key = "logs"          # Links to storage_accounts["logs"]
  }
}
```

### Existing Resources (tfwrapper)

Reference existing Azure resources by full resource ID:

```hcl
existing_resource_groups = {
  "platform" = "/subscriptions/xxx/resourceGroups/rg-platform-lz-001"
}

# Then reference in new resources
storage_accounts = {
  "app" = {
    existing_resource_group_id = "/subscriptions/xxx/resourceGroups/rg-platform-lz-001"
  }
}
```

## Quality Commands

All Terraform projects include quality commands in their Makefiles:

```bash
make fmt                     # Format Terraform files
make fmt-check               # Check formatting (CI-friendly)
make lint                    # Run tflint
make quality                 # Run all quality checks
make validate                # Validate configuration
```

## Testing

### Python Tests

```bash
# Subnet calculator API
cd subnet-calculator/api-fastapi-azure-function
uv run pytest -v                    # Run all tests (30 tests)
./test_endpoints.sh --detailed      # Test all endpoints

# Subnet calculator frontend
cd subnet-calculator/frontend-python-flask
uv run pytest -v                    # Run all tests
```

### Terraform Validation

```bash
# tfwrapper
cd terraform/claranet-tfwrapper
make validate STACK=platform ENV=dev REGION=uks

# Terragrunt
cd terraform/terragrunt
make validate
```

## Excluded from Git

- `terraform/reference/` - Cloned module repositories
- `terraform/claranet-tfwrapper/.run/` - Azure CLI cache
- `**/.terraform/` - Provider cache
- `**/.terragrunt-cache/` - Terragrunt cache
- `*.tfstate*` - State files
- `*.tfvars` - Variable files (may contain sensitive data)
- `conf/state.yml` - Backend configuration (sensitive)
- `.venv/`, `venv/`, `__pycache__/` - Python artifacts

## Important Files

- `.pre-commit-config.yaml` - Pre-commit hook configuration
- `.gitleaks.toml` - Secret scanning rules
- `.markdownlint.yaml` - Markdown linting rules
- `setup-security.sh` - Automated security tool installation (macOS)

## Troubleshooting

### Terraform State Lock Issues

```bash
# tfwrapper
make unlock STACK=platform ENV=dev REGION=uks LOCK_ID=<lock-id-from-error>

# Terragrunt
cd ps-az-sbx/app-a
tofu force-unlock <lock-id>
```

### Azure Backend Permission Errors

When using Azure AD auth (`use_azuread_auth = true`), you need **Storage Blob Data Owner** role:

```bash
USER_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --role "Storage Blob Data Owner" \
  --assignee $USER_ID \
  --scope "/subscriptions/xxx/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/stbackend"
```

### Missing Environment Variables

```bash
# tfwrapper
source terraform/claranet-tfwrapper/setup-env.sh

# Terragrunt
source terraform/terragrunt/setup-env.sh
make check-env                       # Verify all variables set
```

## Git Workflow

This repository uses:

- **Main branch**: `main`
- **Pre-commit hooks**: Automatically run on commit
- **No emoji policy**: Do not write emojis in markdown files. Markdown linting checks for emojis and will fail if any are present.
