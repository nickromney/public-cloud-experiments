# Shared Deployment Scripts

This directory contains shared build and deployment scripts used across multiple Terragrunt stacks.

## Scripts

### `build-function-zip.sh`

Builds an optimized deployment package for Azure Function Apps.

**Usage:**

```bash
./build-function-zip.sh [output-path]
```

**Features:**

- Creates minimal deployment zip (only essential files)
- Excludes test files, development tools, and artifacts
- Includes: auth.py, config.py, function_app.py, host.json, requirements.txt
- Output size: ~16KB (before remote build)

**Default output:** `./function-app.zip`

**Example:**

```bash
# Use default output path
./build-function-zip.sh

# Specify custom output path
./build-function-zip.sh /tmp/my-function-app.zip
```

### `build-deployment-zip.sh`

Builds deployment package for React Web App with shared-frontend dependency.

**Environment Variables:**

- `API_BASE_URL` - Backend API URL (default: `https://func-subnet-calc-react-api.azurewebsites.net`)

**Usage:**

```bash
API_BASE_URL="https://api.example.com" ./build-deployment-zip.sh [output-path]
```

**Features:**

- Builds shared-frontend dependency
- Builds frontend-react with Vite
- Fixes import paths for deployment structure
- Includes runtime configuration (JWT auth settings)
- Cleans up unnecessary files (node_modules, test artifacts)

**Default output:** `./react-app.zip`

**Example:**

```bash
# Use default API URL
./build-deployment-zip.sh

# Specify custom API URL
API_BASE_URL="https://my-apim-gateway.azure-api.net/subnet-calc" \
  ./build-deployment-zip.sh /tmp/react-app.zip
```

## Design Principles

**Shared scripts follow these principles:**

1. **No hardcoded paths** - All paths are computed relative to script location
2. **Configurable via environment variables** - Allow customization without editing
3. **Idempotent** - Can be run multiple times safely
4. **Verbose output** - Clear progress messages for debugging
5. **Error handling** - Use `set -e` to fail fast on errors

## Integration with Stacks

Stacks reference these scripts in their Makefiles using relative paths:

```makefile
SCRIPT_DIR := $(abspath ../../deployment-scripts)

deploy-function:
 @$(SCRIPT_DIR)/build-function-zip.sh $(STACK_DIR)/function-app.zip
 # ... deploy to Azure ...
```

## Repository Structure

```text
terraform/terragrunt/
├── deployment-scripts/          # THIS DIRECTORY
│   ├── README.md
│   ├── build-function-zip.sh
│   └── build-deployment-zip.sh
├── modules/                     # Shared Terraform modules
├── personal-sub/                # Personal subscription stacks
│   ├── subnet-calc-react-webapp/
│   └── subnet-calc-react-webapp-apim/
└── Makefile                     # Root-level commands
```

## Development

When modifying these scripts:

1. **Test across all stacks** - Changes affect multiple deployments
2. **Maintain backward compatibility** - Don't break existing integrations
3. **Update documentation** - Keep this README current
4. **Version carefully** - Consider impact on CI/CD pipelines

## Related Documentation

- [Function App Deployment Guide](../personal-sub/subnet-calc-react-webapp-apim/README.md#step-3-deploy-function-app)
- [Web App Deployment Guide](../personal-sub/subnet-calc-react-webapp-apim/README.md#step-4-deploy-web-app)
- [Root Makefile](../Makefile) - Stack-level orchestration
