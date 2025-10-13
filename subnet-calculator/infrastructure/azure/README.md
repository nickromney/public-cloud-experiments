# Subnet Calculator - Azure Infrastructure

Shell scripts for deploying the subnet calculator to Azure using Static Web Apps and Azure Functions.

**[Complete Deployment Guide](../../docs/AZURE_DEPLOYMENT.md)** - Comprehensive documentation including troubleshooting, region considerations, and production recommendations.

## Architecture

### Option 1: Direct Deployment (Simple)

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

**Use when:** Quick testing, demos, development

**Scripts:** 00, 10, 20, 21/22, 99

### Option 2: API Management (Production-Ready)

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
│   Azure API Management (Dev SKU)    │
│  - Gateway / reverse proxy          │
│  - Rate limiting (100 req/min)      │
│  - CORS handling                    │
│  - Authentication (subscription/JWT)│
│  - Header injection (X-User-*)      │
└──────────────┬──────────────────────┘
               │
               │ HTTPS (IP restricted)
               │
┌──────────────▼──────────────────────┐
│  Azure Function App (Consumption)   │
│  - Python 3.11                      │
│  - FastAPI                          │
│  - Subnet calculation API           │
│  - Only accepts APIM traffic        │
│  - Trusts X-User-* headers          │
└─────────────────────────────────────┘
```

**Use when:** Production, requiring auth, rate limiting, IP restrictions

**Scripts:** 00, 10, 30, 31, 32, 23, 20 (with USE_APIM=true), 99

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
- **2x** - Deployment scripts (20-22: direct, 23: APIM mode)
- **3x** - API Management scripts
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

## Quick Start - API Management (Production)

Use this approach for production deployments with authentication, rate limiting, and IP restrictions.

### 1. Create Infrastructure

```bash
# Set your resource group
export RESOURCE_GROUP="1-xxxxx-playground-sandbox"  # For Pluralsight sandbox
# or
export RESOURCE_GROUP="rg-subnet-calc"  # For your own subscription

# Create Static Web App (Free SKU)
./00-static-web-app.sh

# Create Function App (Consumption plan)
./10-function-app.sh

# Create API Management (Developer SKU - takes ~45 minutes!)
PUBLISHER_EMAIL="your@email.com" \
PUBLISHER_NAME="Your Name" \
./30-apim-instance.sh
```

### 2. Configure APIM

```bash
# Import Function App API into APIM
RESOURCE_GROUP="xxx" \
APIM_NAME="apim-subnet-calc-12345" \
FUNCTION_APP_NAME="func-subnet-calc-67890" \
./31-apim-backend.sh

# Apply authentication policies (choose one mode)
RESOURCE_GROUP="xxx" \
APIM_NAME="apim-subnet-calc-12345" \
AUTH_MODE=subscription \
./32-apim-policies.sh

# AUTH_MODE options:
# - none: Open access with rate limiting only
# - subscription: Requires Ocp-Apim-Subscription-Key header (recommended for sandbox)
# - jwt: Requires Azure Entra ID token (NOT supported in Pluralsight sandbox)
```

### 3. Deploy Application with APIM

```bash
# Deploy Function App in APIM mode (IP restricted)
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-67890" \
APIM_NAME="apim-subnet-calc-12345" \
./23-deploy-function-apim.sh

# Deploy frontend pointing to APIM gateway
RESOURCE_GROUP="xxx" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
USE_APIM=true \
APIM_NAME="apim-subnet-calc-12345" \
./20-deploy-frontend.sh
```

### 4. Test APIM Deployment

```bash
# Get APIM gateway URL
APIM_GATEWAY=$(az apim show --name apim-subnet-calc-12345 --resource-group $RESOURCE_GROUP --query gatewayUrl -o tsv)

# Get subscription key (if using subscription mode)
SUBSCRIPTION_KEY=$(az apim subscription list-secrets \
  --resource-group $RESOURCE_GROUP \
  --service-name apim-subnet-calc-12345 \
  --sid subnet-calc-subscription \
  --query primaryKey -o tsv)

# Test API through APIM
curl -H "Ocp-Apim-Subscription-Key: ${SUBSCRIPTION_KEY}" \
  ${APIM_GATEWAY}/subnet-calc/api/v1/health

# Verify direct Function App access is blocked (should return 403)
FUNC_URL=$(az functionapp show --name func-subnet-calc-67890 --resource-group $RESOURCE_GROUP --query defaultHostName -o tsv)
curl https://${FUNC_URL}/api/v1/health
# Expected: {"detail":"Client IP is not allowed"}

# Visit the web app
SWA_URL=$(az staticwebapp show --name swa-subnet-calc --resource-group $RESOURCE_GROUP --query defaultHostname -o tsv)
open https://${SWA_URL}
```

### 5. Cleanup

```bash
# Delete all resources including APIM (keeps resource group)
./99-cleanup.sh
# Note: APIM deletion takes 15-20 minutes in background
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

### 23-deploy-function-apim.sh

Deploys the Function API to Azure Function App configured for API Management.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc"  # Function App name
export APIM_NAME="apim-subnet-calc"         # APIM instance name
```

**Usage:**

```bash
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-12345" \
APIM_NAME="apim-subnet-calc-67890" \
./23-deploy-function-apim.sh
```

**What it does:**

1. Sets `AUTH_METHOD=apim` on Function App (trusts X-User-* headers from APIM)
2. Gets APIM public IP addresses
3. Adds IP restrictions to Function App (only accepts APIM traffic)
4. Disables CORS on Function App (APIM handles it)
5. Deploys function code with remote build

**Security:**

- Function App only accepts traffic from APIM IPs
- Direct access returns 403 Forbidden
- Function trusts X-User-ID and X-User-Name headers injected by APIM

**Prerequisites:**

- Function App must exist (run `10-function-app.sh`)
- APIM instance must exist (run `30-apim-instance.sh`)
- APIM backend must be configured (run `31-apim-backend.sh`)

### 30-apim-instance.sh

Creates an Azure API Management instance.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"           # Resource group name
export LOCATION="eastus"                         # Azure region (auto-detected if RG exists)
export APIM_NAME="apim-subnet-calc"              # APIM name (auto-generated with random suffix if not set)
export APIM_SKU="Developer"                      # SKU (Developer, Basic, Standard, Consumption)
export PUBLISHER_EMAIL="your@email.com"          # Required: Admin email
export PUBLISHER_NAME="Your Name"                # Publisher name (defaults to email if not set)
```

**Usage:**

```bash
# Basic usage (uses defaults)
PUBLISHER_EMAIL="your@email.com" ./30-apim-instance.sh

# Full configuration
RESOURCE_GROUP="rg-subnet-calc" \
LOCATION="eastus" \
APIM_NAME="apim-subnet-calc" \
APIM_SKU="Developer" \
PUBLISHER_EMAIL="your@email.com" \
PUBLISHER_NAME="Your Organization" \
./30-apim-instance.sh
```

**Provisioning time:**

- **Developer SKU**: ~45 minutes
- **Basic/Standard SKU**: ~45-60 minutes
- **Consumption SKU**: ~2-5 minutes

Script polls for completion and shows elapsed time.

**SKU comparison:**

- **Developer**: $50/month, full features, not SLA-backed (recommended for testing)
- **Basic**: $150/month, 99.95% SLA, 1 unit
- **Standard**: $700/month, 99.95% SLA, 1 unit
- **Consumption**: Pay-per-use, 99.95% SLA, limited features

**Output:**

- APIM name and gateway URL
- Portal URLs (publisher, developer, management)

### 31-apim-backend.sh

Configures APIM backend by importing Function App OpenAPI spec.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export APIM_NAME="apim-subnet-calc"         # APIM instance name
export FUNCTION_APP_NAME="func-subnet-calc"  # Function App name
export API_PATH="subnet-calc"               # API path in APIM gateway (default: subnet-calc)
export API_DISPLAY_NAME="Subnet Calculator API"  # Display name in APIM portal
```

**Usage:**

```bash
RESOURCE_GROUP="xxx" \
APIM_NAME="apim-subnet-calc-12345" \
FUNCTION_APP_NAME="func-subnet-calc-67890" \
./31-apim-backend.sh

# Custom API path
RESOURCE_GROUP="xxx" \
APIM_NAME="apim-subnet-calc-12345" \
FUNCTION_APP_NAME="func-subnet-calc-67890" \
API_PATH="api/v1/calculator" \
./31-apim-backend.sh
```

**What it does:**

1. Downloads OpenAPI spec from Function App (`/api/v1/openapi.json`)
2. Imports API into APIM with all operations
3. Links APIM backend to Function App URL
4. Configures HTTPS protocol and subscription requirement

**Prerequisites:**

- Function App must exist and be running (run `10-function-app.sh` and deploy)
- APIM instance must exist and be provisioned (run `30-apim-instance.sh` and wait)

**Output:**

- API imported with path `/subnet-calc` (or custom path)
- APIM URL: `https://{apim-gateway}/subnet-calc/api/v1/...`

### 32-apim-policies.sh

Applies authentication policies to APIM API.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc"      # Resource group name
export APIM_NAME="apim-subnet-calc"         # APIM instance name
export API_PATH="subnet-calc"               # API path (must match 31-apim-backend.sh)
export AUTH_MODE="subscription"             # Auth mode: none, subscription, jwt
export RATE_LIMIT="100"                     # Requests per minute (default: 100)
```

**Usage:**

```bash
# Subscription key authentication (recommended)
RESOURCE_GROUP="xxx" \
APIM_NAME="apim-subnet-calc-12345" \
AUTH_MODE=subscription \
./32-apim-policies.sh

# Open access with rate limiting only
AUTH_MODE=none ./32-apim-policies.sh

# JWT authentication (requires Entra ID - NOT supported in Pluralsight sandbox)
AUTH_MODE=jwt ./32-apim-policies.sh
```

**Authentication modes:**

1. **none** - Open access with rate limiting
   - No authentication required
   - Rate limiting: 100 requests/minute per IP
   - CORS enabled for all origins
   - Injects anonymous user headers

2. **subscription** - Subscription key authentication (recommended for sandbox)
   - Requires `Ocp-Apim-Subscription-Key` header
   - Rate limiting: 100 requests/minute per subscription
   - CORS enabled for all origins
   - Injects subscription ID as X-User-ID
   - Script creates subscription and outputs keys

3. **jwt** - JWT token authentication (requires Entra ID)
   - Requires `Authorization: Bearer <token>` header
   - Validates against Azure Entra ID
   - Rate limiting: 100 requests/minute per user
   - CORS enabled for all origins
   - Injects user OID and email from JWT claims
   - **NOT supported in Pluralsight sandbox**

**Subscription mode output:**

```bash
Primary Key: abc123...
Secondary Key: def456...

Test API with subscription key:
curl -H "Ocp-Apim-Subscription-Key: abc123..." \
  https://{apim-gateway}/subnet-calc/api/v1/health
```

**Policy files:**

Policies are in `policies/` directory:

- `inbound-none.xml` - Open access policy
- `inbound-subscription.xml` - Subscription key policy
- `inbound-jwt.xml` - JWT validation policy
- `README.md` - Policy documentation

**Prerequisites:**

- APIM instance must exist (run `30-apim-instance.sh`)
- API must be imported (run `31-apim-backend.sh`)

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

### Option 1: Direct Deployment

All scripts use the cheapest Azure SKUs:

- **Static Web App**: Free tier (100 GB bandwidth/month)
- **Function App**: Consumption plan (pay per execution)
- **Storage Account**: Standard LRS (cheapest redundancy)

**Estimated monthly cost (light usage):**

- Static Web App: $0 (Free tier)
- Function App: ~$0-5 (1M free executions, then $0.20/million)
- Storage: ~$0.50-1.00 (function storage only)

**Total: ~$1-6/month** for light usage

### Option 2: API Management

Adds APIM layer for production deployments:

- **Static Web App**: Free tier (100 GB bandwidth/month)
- **Function App**: Consumption plan (pay per execution)
- **Storage Account**: Standard LRS (cheapest redundancy)
- **API Management**: Developer SKU (for testing/development)

**Estimated monthly cost:**

- Static Web App: $0 (Free tier)
- Function App: ~$0-5 (1M free executions, then $0.20/million)
- Storage: ~$0.50-1.00 (function storage only)
- APIM Developer: ~$50/month (not SLA-backed, for testing only)

**Total: ~$51-56/month** with APIM Developer SKU

**Production APIM SKUs:**

- **Basic**: ~$150/month (99.95% SLA, 1 unit, 1 region)
- **Standard**: ~$700/month (99.95% SLA, 1 unit, 1 region)
- **Consumption**: Pay-per-use (~$3.50 per million calls, 99.95% SLA)

APIM Consumption tier may be cheaper for low-traffic APIs.

## Security Considerations

### Option 1: Direct Deployment (No Auth)

The simple deployment approach has **no authentication** by default:

- Function API is publicly accessible
- No JWT tokens required
- No rate limiting (Azure default throttling only)
- Suitable for demonstrations and testing
- **NOT suitable for production with sensitive data**

**To add JWT authentication:**

```bash
# Deploy with JWT auth
./21-deploy-function.sh  # Don't set DISABLE_AUTH=true

# Set JWT secret
az functionapp config appsettings set \
  --name func-subnet-calc \
  --resource-group rg-subnet-calc \
  --settings JWT_SECRET_KEY='your-secret-key-here'
```

### Option 2: API Management (Production Security)

The APIM deployment provides production-grade security:

**Security features:**

- **API Gateway**: Single entry point for all API traffic
- **IP Restrictions**: Function App only accepts APIM traffic (blocks direct access)
- **Rate Limiting**: 100 requests/minute per user/subscription/IP
- **CORS Handling**: Centralized at gateway level
- **Authentication**: Three modes (none, subscription, JWT)
- **Header Injection**: Trusted X-User-* headers from APIM to Function

**Authentication modes:**

1. **Subscription Key** (recommended for sandbox):
   - Requires `Ocp-Apim-Subscription-Key` header
   - Easy to test and manage
   - Works in Pluralsight sandbox
   - Suitable for API integrations

2. **JWT / Entra ID** (production SSO):
   - Requires `Authorization: Bearer <token>` header
   - Validates against Azure Entra ID
   - Enterprise single sign-on
   - **NOT supported in Pluralsight sandbox**

3. **Open Access** (development):
   - No authentication required
   - Rate limiting only
   - Useful for development/testing

**Direct access blocked:**

```bash
# Direct Function App URL returns 403 Forbidden
curl https://func-subnet-calc.azurewebsites.net/api/v1/health
# {"detail":"Client IP is not allowed"}

# Must access through APIM gateway
curl -H "Ocp-Apim-Subscription-Key: abc123..." \
  https://apim-xyz.azure-api.net/subnet-calc/api/v1/health
# {"status":"healthy"}
```

### Security Best Practices

**For testing/demos:**

- Use direct deployment with `DISABLE_AUTH=true`
- Or APIM with `AUTH_MODE=none` for rate limiting only

**For production:**

- Use APIM with `AUTH_MODE=subscription` (API integrations)
- Use APIM with `AUTH_MODE=jwt` (user-facing apps with SSO)
- Never use `DISABLE_AUTH=true` on Function App
- Configure IP restrictions beyond APIM if needed
- Use Application Insights for monitoring and alerting

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

**Direct deployment:**

CORS is configured to allow all origins (`*`) by default. If you need to restrict:

```bash
az functionapp cors remove --name func-subnet-calc --resource-group rg-subnet-calc --allowed-origins "*"
az functionapp cors add --name func-subnet-calc --resource-group rg-subnet-calc --allowed-origins "https://your-swa-url.azurestaticapps.net"
```

**APIM deployment:**

CORS is handled by APIM policies. Function App CORS should be disabled when using APIM.

### APIM Provisioning Taking Too Long

APIM Developer SKU takes ~45 minutes to provision. This is normal.

```bash
# Check provisioning status
az apim show --name apim-subnet-calc --resource-group rg-subnet-calc --query provisioningState -o tsv

# Expected states:
# - Creating: Still provisioning
# - Activating: Final activation step
# - Succeeded: Ready to use
# - Failed: Check error message
```

The `30-apim-instance.sh` script polls automatically and shows elapsed time.

### APIM: 403 Forbidden with Subscription Key

If you get 403 even with a valid subscription key:

```bash
# Verify subscription exists and is active
az apim subscription show \
  --resource-group rg-subnet-calc \
  --service-name apim-subnet-calc \
  --sid subnet-calc-subscription

# Check policy is applied correctly
az apim api policy show \
  --resource-group rg-subnet-calc \
  --service-name apim-subnet-calc \
  --api-id subnet-calc

# Regenerate keys if needed
az apim subscription regenerate-primary-key \
  --resource-group rg-subnet-calc \
  --service-name apim-subnet-calc \
  --sid subnet-calc-subscription
```

### Function App: 403 Forbidden (Direct Access)

This is expected when using APIM mode. Function App is IP-restricted to only accept APIM traffic.

```bash
# Check IP restrictions
az functionapp config access-restriction show \
  --name func-subnet-calc \
  --resource-group rg-subnet-calc

# To allow direct access again (not recommended):
# 1. Remove IP restrictions
# 2. Change AUTH_METHOD back to jwt or disable
# 3. Re-enable CORS
```

### APIM: Cannot Import OpenAPI Spec

If `31-apim-backend.sh` fails to download OpenAPI spec:

```bash
# Check Function App is running
az functionapp show --name func-subnet-calc --resource-group rg-subnet-calc --query state -o tsv

# Test OpenAPI endpoint manually
FUNC_URL=$(az functionapp show --name func-subnet-calc --resource-group rg-subnet-calc --query defaultHostName -o tsv)
curl https://${FUNC_URL}/api/v1/openapi.json

# Function App may be in cold start - wait 2-3 minutes and retry
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

### Option 1: Direct Deployment

1. **Add VNet Integration** - Connect Function App to private network
2. **Add Custom Domains** - Configure custom DNS
3. **Add Application Insights** - Telemetry and monitoring
4. **Add Terraform** - Infrastructure as Code version
5. **Upgrade to APIM** - Follow Option 2 for production-grade API gateway

### Option 2: API Management (Already Implemented)

The APIM deployment scripts (30-32, 23) provide:

- API gateway with rate limiting
- Multiple authentication modes (none, subscription, JWT)
- IP restrictions (Function App behind APIM)
- CORS handling at gateway level
- Header injection for user context

**Additional enhancements:**

1. **Add Custom Domains** - Configure custom DNS for APIM gateway
2. **Add Application Insights** - Telemetry, monitoring, and distributed tracing
3. **Add VNet Integration** - Private network for Function App (remove public access)
4. **Add Multiple Regions** - APIM multi-region deployment for HA
5. **Add Entra ID Integration** - Enable JWT authentication mode (not for sandbox)
6. **Add Terraform** - Infrastructure as Code version of APIM deployment

## References

### Core Services

- [Azure Static Web Apps Documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Azure Functions Python Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/)

### API Management

- [Azure API Management Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
- [API Management Policies Reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
- [APIM Policy Expressions](https://learn.microsoft.com/en-us/azure/api-management/api-management-policy-expressions)
- [APIM Authentication Policies](https://learn.microsoft.com/en-us/azure/api-management/api-management-authentication-policies)
- [APIM Access Restriction Policies](https://learn.microsoft.com/en-us/azure/api-management/api-management-access-restriction-policies)
- [Import OpenAPI Spec to APIM](https://learn.microsoft.com/en-us/azure/api-management/import-api-from-oas)
- [APIM Pricing](https://azure.microsoft.com/en-us/pricing/details/api-management/)

### Security

- [Function App IP Restrictions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options)
- [APIM IP Filtering](https://learn.microsoft.com/en-us/azure/api-management/api-management-access-restriction-policies#RestrictCallerIPs)
- [Azure Entra ID Integration with APIM](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-protect-backend-with-aad)
