# Subnet Calculator Static Web Apps

Terragrunt project managing existing Azure Static Web Apps and their linked Function Apps for the Subnet Calculator application.

## Resources Managed

### Static Web Apps

1. **swa-subnet-calc-noauth** (Standard tier)
   - Custom domain: static-swa-no-auth.publiccloudexperiments.net
   - Public network access enabled
   - No linked backend (calls Function App directly)

2. **swa-subnet-calc-entraid-linked** (Standard tier)
   - Custom domain: static-swa-entraid-linked.publiccloudexperiments.net
   - Linked backend: func-subnet-calc-entraid-linked
   - Entra ID authentication configured

3. **swa-subnet-calc-private-endpoint** (Standard tier)
   - Custom domain: static-swa-private-endpoint.publiccloudexperiments.net
   - Public network access: Disabled
   - Private endpoint configured
   - Linked backend: func-subnet-calc-asp-46195

### Function Apps

1. **func-subnet-calc-jwt**
   - Plan: ASP-rgsubnetcalc-4e5a (FlexConsumption)
   - Runtime: Python 3.11
   - Auth: JWT
   - Custom domain: subnet-calc-fa-jwt-auth.publiccloudexperiments.net
   - Storage: stsubnetcalc22531

2. **func-subnet-calc-entraid-linked**
   - Plan: ASP-rgsubnetcalc-d642 (FlexConsumption)
   - Runtime: Python 3.11
   - Auth: SWA (X-MS-CLIENT-PRINCIPAL header)
   - Custom domain: subnet-calc-fa-entraid-linked.publiccloudexperiments.net
   - Storage: stsubnetcalc34188

3. **func-subnet-calc-asp-46195**
   - Plan: asp-subnet-calc-stack16 (B1)
   - Runtime: Python 3.11
   - Auth: None
   - No custom domain (private endpoint only)
   - Storage: stfuncprivateep61925

## Quick Start

### Setup Environment

Before running any Terragrunt commands, set up environment variables:

```bash
# Option 1: Non-interactive CI mode (recommended for scripts/automation)
cd ../../
eval "$(./setup-env.sh --group rg-subnet-calc --ci 2>&1 | grep '^export')"

# Option 2: Interactive mode
cd ../../
./setup-env.sh --group rg-subnet-calc
# Then copy and paste the export commands shown

# Verify environment variables are set
make check-env
```

The setup script will:

- Detect your Azure subscription and tenant
- Find or create a storage account for Terraform state
- Display export commands for you to run

**Flags:**

- `--group RESOURCE_GROUP` - Specify the resource group for backend storage
- `--ci` - Non-interactive mode (auto-accepts defaults, no prompts)

The `check-env` target verifies all required environment variables are set before running Terragrunt commands.

### Initialize and Import

```bash
# Initialize Terragrunt
make init

# Import all existing resources
make import-all

# Or import incrementally
make import-plans
make import-storage
make import-functions
make import-swas
make import-custom-domains

# Verify imports
make plan
```

### Common Operations

```bash
# Plan changes
make plan

# Apply changes
make apply

# Format code
make fmt

# Validate configuration
make validate

# Clean cached files
make clean
```

## Import Details

Resources are imported from the existing Azure deployment. The Makefile provides targets for importing:

- **App Service Plans** (3): FlexConsumption and B1 plans
- **Storage Accounts** (3): For Function App storage
- **Function Apps** (3): JWT, Entra ID linked, and private endpoint versions
- **Static Web Apps** (3): No-auth, Entra ID linked, and private endpoint versions
- **Custom Domains**: SWA custom domains and Function App hostname bindings

## DNS Management

Custom domain DNS records are managed separately in:
`terraform/terragrunt/cloudflare-publiccloudexperiments/dns-core/`

This project only imports and manages the Azure-side custom domain configuration (validation, SSL certificates, hostname bindings).

## Architecture Notes

### Stack 1: Public SWA + JWT Function

- **SWA**: swa-subnet-calc-noauth (public)
- **Function**: func-subnet-calc-jwt (public, JWT auth)
- **Domain**: static-swa-no-auth.publiccloudexperiments.net → subnet-calc-fa-jwt-auth.publiccloudexperiments.net
- **Use case**: Public API with JWT authentication

### Stack 2: SWA + Entra ID + Linked Backend

- **SWA**: swa-subnet-calc-entraid-linked (public, Entra ID auth)
- **Function**: func-subnet-calc-entraid-linked (linked backend)
- **Domain**: static-swa-entraid-linked.publiccloudexperiments.net
- **Use case**: Enterprise auth with SWA proxy to backend

### Stack 3: Private Endpoint

- **SWA**: swa-subnet-calc-private-endpoint (private endpoint)
- **Function**: func-subnet-calc-asp-46195 (private endpoint)
- **Domain**: static-swa-private-endpoint.publiccloudexperiments.net
- **Use case**: High security with network isolation

## Related Documentation

- Deployment scripts: `subnet-calculator/infrastructure/azure/azure-stack-*.sh`
- Module source: `terraform/terragrunt/modules/azure-static-web-app/`
- DNS configuration: `terraform/terragrunt/cloudflare-publiccloudexperiments/dns-core/`
