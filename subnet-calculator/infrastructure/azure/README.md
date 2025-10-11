# Subnet Calculator - Azure Infrastructure

Shell scripts for deploying the subnet calculator to Azure using Static Web Apps and Azure Functions.

**[Complete Deployment Guide](../../docs/AZURE_DEPLOYMENT.md)** - Comprehensive documentation including troubleshooting, region considerations, and production recommendations.

## Architecture

```text
┌─────────────────────────────────────┐
│   Azure Static Web App (Free SKU)  │
│  - TypeScript Vite SPA              │
│  - Static HTML + JS                 │
│  - Global CDN                       │
└──────────────┬──────────────────────┘
               │
               │ HTTPS
               │
┌──────────────▼──────────────────────┐
│  Azure Function App (Consumption)   │
│  - Python 3.11                      │
│  - FastAPI                          │
│  - Subnet calculation API           │
│  - Public access (no auth)          │
└─────────────────────────────────────┘
```

## Prerequisites

**Check prerequisites:**

```bash
./prerequisites.sh
```

**Required tools:**

- Azure CLI (`brew install azure-cli`)
- Azure Functions Core Tools (`brew install azure-functions-core-tools`)
- Node.js and npm (`brew install node`)
- Python 3.11+ (`brew install python@3.11`)
- uv (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

**Optional (auto-installs during deployment):**

- Static Web Apps CLI (`npm install -g @azure/static-web-apps-cli`)

**Login:**

```bash
az login
```

## Script Numbering Convention

- **0x** - Static Web App scripts
- **1x** - Function App scripts
- **2x** - Deployment scripts
- **9x** - Cleanup scripts

## Quick Start

### 1. Create Infrastructure

```bash
# Set your resource group (or use default: rg-subnet-calc)
export RESOURCE_GROUP="1-xxxxx-playground-sandbox"  # For Pluralsight sandbox
# or
export RESOURCE_GROUP="rg-subnet-calc"  # For your own subscription

# Create Static Web App (Free SKU)
./00-static-web-app.sh

# Create Function App (Consumption plan)
./10-function-app.sh
```

### 2. Deploy Application

```bash
# Deploy Function API (with auth disabled for simplicity)
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-12345" \
DISABLE_AUTH=true \
./22-deploy-function-zip.sh

# Deploy TypeScript Vite frontend (recommended)
RESOURCE_GROUP="xxx" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
API_URL="https://func-subnet-calc-12345.azurewebsites.net" \
./20-deploy-frontend.sh
```

### 3. Test

```bash
# Get URLs from Azure
SWA_URL=$(az staticwebapp show --name swa-subnet-calc --resource-group $RESOURCE_GROUP --query defaultHostname -o tsv)
FUNC_URL=$(az functionapp show --name func-subnet-calc --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv)

# Test Function API health
curl https://${FUNC_URL}/api/v1/health

# Visit the web app
open https://${SWA_URL}
```

### 4. Cleanup

```bash
# Delete resources but keep resource group (sandbox-friendly)
./99-cleanup.sh

# Delete everything including resource group
DELETE_RG=true ./99-cleanup.sh
```

## Scripts

### 00-static-web-app.sh

Creates an Azure Static Web App for hosting the frontend.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export LOCATION="eastus"                    # Azure region (auto-detected if RG exists)
export STATIC_WEB_APP_NAME="swa-subnet-calc"  # SWA name
export STATIC_WEB_APP_SKU="Free"           # SKU (Free or Standard)
```

**Usage:**

```bash
./00-static-web-app.sh
```

**Output:**

- Static Web App URL
- Deployment token (for GitHub Actions or manual deployment)

### 10-function-app.sh

Creates an Azure Function App with Consumption plan for the API.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export LOCATION="eastus"                    # Azure region (auto-detected if RG exists)
export FUNCTION_APP_NAME="func-subnet-calc"  # Function App name
export STORAGE_ACCOUNT_NAME="stsubnetcalc123456"  # Storage (auto-generated if not set)
export PYTHON_VERSION="3.11"                # Python runtime version
```

**Usage:**

```bash
./10-function-app.sh
```

**Output:**

- Function App URL
- CORS configured for all origins
- HTTPS only enabled

### 20-deploy-frontend.sh

Deploys a frontend to Azure Static Web App.

**Supported frontends:**

- `typescript` - TypeScript + Vite SPA (recommended)
- `static` - Static HTML + vanilla JavaScript
- `flask` - Not supported (requires server runtime)

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export STATIC_WEB_APP_NAME="swa-subnet-calc"  # SWA name
export FRONTEND="typescript"                # Frontend type
export API_URL="https://func-xyz.azurewebsites.net"  # Optional: API URL
```

**Usage:**

```bash
# Deploy TypeScript frontend
FRONTEND=typescript ./20-deploy-frontend.sh

# Deploy with custom API URL
FRONTEND=typescript API_URL=https://my-api.azurewebsites.net ./20-deploy-frontend.sh

# Deploy static HTML frontend
FRONTEND=static ./20-deploy-frontend.sh
```

**Requirements:**

- Azure Static Web Apps CLI (`npm install -g @azure/static-web-apps-cli`)
- Node.js and npm (for TypeScript builds)

### 21-deploy-function.sh

Deploys the Function API to Azure Function App.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc"  # Function App name
export DISABLE_AUTH="false"                 # Disable JWT auth (true/false)
```

**Usage:**

```bash
# Deploy with auth disabled (public access)
DISABLE_AUTH=true ./21-deploy-function.sh

# Deploy with JWT auth enabled
./21-deploy-function.sh
```

**Authentication:**

- **Disabled** (`DISABLE_AUTH=true`): Public API, no token required
- **Enabled** (default): Requires JWT token and `JWT_SECRET_KEY` app setting

To set JWT secret after deployment:

```bash
az functionapp config appsettings set \
  --name func-subnet-calc \
  --resource-group rg-subnet-calc \
  --settings JWT_SECRET_KEY='your-secret-key-here'
```

### 99-cleanup.sh

Deletes all Azure resources created by these scripts.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export STATIC_WEB_APP_NAME="swa-subnet-calc"  # SWA name
export FUNCTION_APP_NAME="func-subnet-calc"  # Function App name
export DELETE_RG="false"                    # Delete RG (true/false)
```

**Usage:**

```bash
# Delete resources, keep resource group (sandbox-safe)
./99-cleanup.sh

# Delete everything including resource group
DELETE_RG=true ./99-cleanup.sh
```

## Sandbox Environments (Pluralsight, etc.)

These scripts work in sandbox environments with limitations:

**Works:**

- Pre-existing resource groups
- Auto-detects location from existing RG
- Creates resources without RG creation permissions
- Deletes resources without deleting the RG

**Limitations:**

- Cannot create new resource groups (use pre-existing sandbox RG)
- Limited regions (usually `eastus`, `westus2`)
- No Entra ID / custom domains in some sandboxes
- 4-hour expiration in Pluralsight sandboxes

**Example for Pluralsight:**

```bash
# Use the sandbox resource group
export RESOURCE_GROUP="1-abc12345-playground-sandbox"

# Run scripts normally
./00-static-web-app.sh
./10-function-app.sh
DISABLE_AUTH=true ./21-deploy-function.sh
FRONTEND=typescript ./20-deploy-frontend.sh

# Cleanup (preserves the sandbox RG)
./99-cleanup.sh
```

## Cost Estimation

All scripts use the cheapest Azure SKUs:

- **Static Web App**: Free tier (100 GB bandwidth/month)
- **Function App**: Consumption plan (pay per execution)
- **Storage Account**: Standard LRS (cheapest redundancy)

**Estimated monthly cost (light usage):**

- Static Web App: $0 (Free tier)
- Function App: ~$0-5 (1M free executions, then $0.20/million)
- Storage: ~$0.50-1.00 (function storage only)

**Total: ~$1-6/month** for light usage

## Security Considerations

### Initial Setup (No Auth)

These scripts deploy with **no authentication** by default:

- Function API is publicly accessible
- No JWT tokens required
- Suitable for demonstrations and testing
- **NOT suitable for production with sensitive data**

### Adding Security Later

To add authentication:

1. **JWT Authentication:**

   ```bash
   # Deploy with JWT auth
   ./21-deploy-function.sh  # Don't set DISABLE_AUTH=true

   # Set JWT secret
   az functionapp config appsettings set \
     --name func-subnet-calc \
     --resource-group rg-subnet-calc \
     --settings JWT_SECRET_KEY='your-secret-key-here'
   ```

2. **Azure AD / Entra ID** (future):
   - Requires additional scripts
   - Needs app registrations
   - Not available in all sandbox environments

3. **API Management** (future):
   - Add rate limiting
   - Add IP filtering
   - Add subscription keys

## Troubleshooting

### Static Web App CLI Not Found

```bash
npm install -g @azure/static-web-apps-cli
```

### Function Deployment Fails

```bash
# Check if Function App exists
az functionapp show --name func-subnet-calc --resource-group rg-subnet-calc

# View logs
az functionapp log tail --name func-subnet-calc --resource-group rg-subnet-calc

# Restart Function App
az functionapp restart --name func-subnet-calc --resource-group rg-subnet-calc
```

### Resource Group Not Found

```bash
# Create resource group (if you have permissions)
az group create --name rg-subnet-calc --location eastus

# Or set LOCATION for auto-detection
export LOCATION="eastus"
./00-static-web-app.sh
```

### CORS Errors

CORS is configured to allow all origins (`*`) by default. If you need to restrict:

```bash
az functionapp cors remove --name func-subnet-calc --resource-group rg-subnet-calc --allowed-origins "*"
az functionapp cors add --name func-subnet-calc --resource-group rg-subnet-calc --allowed-origins "https://your-swa-url.azurestaticapps.net"
```

## Known Issues

### Static Web Apps CLI Deprecated Dependencies

The Azure Static Web Apps CLI (v2.0.7) shows warnings about deprecated npm packages:

- `inflight@1.0.6`, `rimraf@2.7.1`, `glob@7.2.3`, `sudo-prompt@8.2.5`

**Impact:** None - these are transitive dependencies in Microsoft's SWA CLI. The warnings are cosmetic and don't affect functionality.

**Resolution:** Microsoft needs to update the SWA CLI. Track progress at: <https://github.com/Azure/static-web-apps-cli/issues>

**Workaround:** None needed - deployments work correctly despite warnings.

### Function App Cold Start

Azure Functions on Consumption plan experience "cold starts" (2-5 minutes) after:

- Initial deployment
- Extended periods of inactivity
- Configuration changes

**Mitigation:** Use Premium plan or keep Function warm with scheduled pings if cold starts are unacceptable.

## Next Steps

1. **Add VNet Integration** - Connect Function App to private network
2. **Add Custom Domains** - Configure custom DNS
3. **Add Entra ID Auth** - Enterprise SSO
4. **Add API Management** - Rate limiting, monitoring
5. **Add Application Insights** - Telemetry and monitoring
6. **Add Terraform** - Infrastructure as Code version

## References

- [Azure Static Web Apps Documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Azure Functions Python Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/)
