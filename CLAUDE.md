# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a multi-project repository for cloud technology experiments, primarily focused on Azure with some AWS. It contains production-ready applications and Infrastructure as Code (IaC) experiments using different tools and patterns.

## Projects

### 1. Subnet Calculator (`subnet-calculator/`)

A full-stack IPv4/IPv6 subnet calculator with multiple backend and frontend implementations.

**Architecture:**

- **2 Backend APIs**: Azure Function (JWT auth) and Container App (no auth)
- **4 Frontend Options**: Flask (server-side), Static HTML (client-side), TypeScript Vite (modern SPA)
- **4 Complete Stacks**: Mix and match backends with frontends
- **Test Coverage**: 188 total tests (108 Azure Function + 60 Container App + 20 Flask)
- **Security**: 4/5 container images have 0 HIGH/CRITICAL vulnerabilities

**Frontend Options:**

1. **Flask + Azure Function** (Stack 1) - Server-side rendering with JWT auth
   - Port: 8000
   - Backend: Azure Function API (port 8080)
   - Auth: JWT with Argon2 hashed passwords
2. **Static HTML + Container App** (Stack 2) - Pure client-side JavaScript
   - Port: 8001
   - Backend: Container App API (port 8090)
   - Auth: None
3. **Flask + Container App** (Stack 3) - Server-side rendering, no auth
   - Port: 8002
   - Backend: Container App API (port 8090)
   - Auth: None
4. **TypeScript Vite + Container App** (Stack 4) - Modern SPA with Playwright tests
   - Port: 3000
   - Backend: Container App API (port 8090)
   - Auth: None
   - Tools: TypeScript, Vite, Playwright, Biome

**Quick Start (All Stacks):**

```bash
cd subnet-calculator
podman-compose up -d
# Stack 1: http://localhost:8000
# Stack 2: http://localhost:8001
# Stack 3: http://localhost:8002
# Stack 4: http://localhost:3000
```

**Quick Start (Stack 4 - Recommended):**

```bash
cd subnet-calculator
podman-compose up api-fastapi-container-app frontend-typescript-vite
# Access at http://localhost:3000
# API docs at http://localhost:8090/api/v1/docs
```

**Backend Development (Azure Function):**

```bash
cd subnet-calculator/api-fastapi-azure-function
uv sync --extra dev          # Install dependencies
uv run pytest -v             # Run tests (108 tests)
func start                   # Run locally (port 7071)
./test_endpoints.sh          # Test all endpoints
```

**Backend Development (Container App):**

```bash
cd subnet-calculator/api-fastapi-container-app
uv sync --extra dev          # Install dependencies
uv run pytest -v             # Run tests (60 tests)
uv run uvicorn app.main:app --reload  # Run locally (port 8000)
```

**Frontend Development (Flask):**

```bash
cd subnet-calculator/frontend-python-flask
uv sync --extra dev          # Install dependencies
uv run pytest -v             # Run tests (20 tests)
uv run flask run             # Run locally (port 5000)
```

**Frontend Development (TypeScript Vite):**

```bash
cd subnet-calculator/frontend-typescript-vite
npm install                  # Install dependencies
npm run dev                  # Run dev server (port 5173)
npm test                     # Run Playwright tests
npm run lint                 # Run Biome linting
npm run check                # Run all checks
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
make precommit               # Run all quality checks (format, lint, test, hooks)
pre-commit run --all-files   # Run all hooks only
gitleaks detect --verbose    # Secret scanning
```

**Configured Hooks:**

- **Gitleaks**: Secret scanning
- **Terraform**: Format, validate, tflint, tfsec (excludes claranet-tfwrapper/)
- **Shellcheck**: Shell script linting
- **Markdownlint**: Markdown formatting and linting (auto-fixes issues)
- **General**: Trailing whitespace, EOF fixer, YAML validation, large files check

### Security Scanning

**Trivy Container Scanning:**

```bash
make trivy-scan              # Scan for HIGH/CRITICAL vulnerabilities (CI gate)
make trivy-scan-all          # Scan for all severity levels (informational)
```

**Current Security Status:**

- **api-fastapi-azure-function**: 429 vulnerabilities (Microsoft base image - Debian 11.11)
- **api-fastapi-container-app**: 0 vulnerabilities (Debian 13.1)
- **frontend-python-flask**: 0 vulnerabilities (Debian 13.1)
- **frontend-html-static**: 0 vulnerabilities (Alpine 3.22.2)
- **frontend-typescript-vite**: 0 vulnerabilities (Alpine 3.22.2)

**Note**: Azure Function vulnerabilities are in the Microsoft-maintained base image and cannot be fixed without a Microsoft update. All application code and other images are secure.

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

# Node.js (for TypeScript frontend)
brew install node

# Terraform/OpenTofu
brew install opentofu tflint tfsec
uv tool install claranet-tfwrapper
brew install terragrunt

# Container runtime
brew install docker          # or podman

# Security scanning
brew install trivy gitleaks
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
# Run all Python tests from root
make python-test                    # 188 tests total (3 projects)

# Individual projects
cd subnet-calculator/api-fastapi-azure-function
uv run pytest -v                    # 108 tests
./test_endpoints.sh --detailed      # Test all endpoints

cd subnet-calculator/api-fastapi-container-app
uv run pytest -v                    # 60 tests

cd subnet-calculator/frontend-python-flask
uv run pytest -v                    # 20 tests
```

### TypeScript Tests

```bash
cd subnet-calculator/frontend-typescript-vite
npm test                            # Playwright E2E tests (headless)
npm run test:headed                 # Run tests with browser visible
npm run test:ui                     # Interactive test UI
```

### Quality Checks

```bash
# Python
make python-lint                    # Run ruff on all Python projects
make python-fmt                     # Format and fix Python code
make python-test                    # Run pytest on all Python projects

# TypeScript
cd subnet-calculator/frontend-typescript-vite
npm run lint                        # Run Biome linting
npm run format                      # Format code with Biome
npm run check                       # Run all checks (lint + type-check)

# All projects
make precommit                      # Run everything (format, lint, test, hooks)
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

## Environment Variables

### Shell-Specific Setup

The project uses environment variables for configuration. Syntax differs between shells.

**Bash:**

```bash
# Azure CLI / Deployment scripts
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-app-secret"
export RESOURCE_GROUP="rg-subnet-calc"
export LOCATION="uksouth"

# Terraform
export ARM_SUBSCRIPTION_ID="subscription-id"
export ARM_TENANT_ID="tenant-id"
export ARM_CLIENT_ID="client-id"
export ARM_CLIENT_SECRET="client-secret"
```

**Nushell:**

```nushell
# Azure CLI / Deployment scripts
$env.AZURE_CLIENT_ID = "your-app-id"
$env.AZURE_CLIENT_SECRET = "your-app-secret"
$env.RESOURCE_GROUP = "rg-subnet-calc"
$env.LOCATION = "uksouth"

# Terraform
$env.ARM_SUBSCRIPTION_ID = "subscription-id"
$env.ARM_TENANT_ID = "tenant-id"
$env.ARM_CLIENT_ID = "client-id"
$env.ARM_CLIENT_SECRET = "client-secret"
```

**Run scripts with environment variables:**

Bash:

```bash
AZURE_CLIENT_ID="xxx" AZURE_CLIENT_SECRET="yyy" ./azure-stack-06-swa-typescript-entraid-linked.sh
```

Nushell:

```nushell
$env.AZURE_CLIENT_ID = "xxx"; $env.AZURE_CLIENT_SECRET = "yyy"; ./azure-stack-06-swa-typescript-entraid-linked.sh
```

## Git Workflow

This repository uses:

- **Main branch**: `main`
- **Pre-commit hooks**: Automatically run on commit
- **No emoji policy**: Do not write emojis in markdown files. Markdown linting checks for emojis and will fail if any are present.
