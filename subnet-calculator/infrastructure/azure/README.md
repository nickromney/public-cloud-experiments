# Subnet Calculator - Azure Infrastructure

Shell scripts for deploying the subnet calculator to Azure using Static Web Apps and Azure Functions.

**[Complete Deployment Guide](../../docs/AZURE_DEPLOYMENT.md)** - Comprehensive documentation including troubleshooting, region considerations, and production recommendations.

## Architecture

### Option 1: Direct Deployment (Simple)

```text
┌─────────────────────────────────────┐
│ Azure Static Web App (Free SKU) │
│ - TypeScript Vite SPA │
│ - Static HTML + JS │
│ - Global CDN │
└──────────────┬──────────────────────┘
 │
 │ HTTPS
 │
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Python 3.11 │
│ - FastAPI │
│ - Subnet calculation API │
│ - Public access (no auth) │
└─────────────────────────────────────┘
```

**Use when:** Quick testing, demos, development

**Scripts:** 00, 10, 20, 21/22, 99

### Option 2: API Management (Production-Ready)

```text
┌─────────────────────────────────────┐
│ Azure Static Web App (Free SKU) │
│ - TypeScript Vite SPA │
│ - Static HTML + JS │
│ - Global CDN │
└──────────────┬──────────────────────┘
 │
 │ HTTPS
 │
┌──────────────▼──────────────────────┐
│ Azure API Management (Dev SKU) │
│ - Gateway / reverse proxy │
│ - Rate limiting (100 req/min) │
│ - CORS handling │
│ - Authentication (subscription/JWT)│
│ - Header injection (X-User-*) │
└──────────────┬──────────────────────┘
 │
 │ HTTPS (IP restricted)
 │
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Python 3.11 │
│ - FastAPI │
│ - Subnet calculation API │
│ - Only accepts APIM traffic │
│ - Trusts X-User-* headers │
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

## Shell Compatibility

The deployment scripts are bash scripts that work with any shell, but environment variable syntax differs between shells.

### Bash / Zsh

```bash
# Set environment variables
export RESOURCE_GROUP="rg-subnet-calc"
export LOCATION="uksouth"
export CUSTOM_DOMAIN="publiccloudexperiments.net"

# Run scripts (they inherit the environment)
./stack-03-swa-typescript-noauth.sh
```

**Automated setup:**

```bash
# Interactive setup (auto-detects resource group)
source ./setup-env.sh

# Then run scripts
./stack-03-swa-typescript-noauth.sh
```

### Nushell

```nushell
# Set environment variables
$env.RESOURCE_GROUP = "rg-subnet-calc"
$env.LOCATION = "uksouth"
$env.CUSTOM_DOMAIN = "publiccloudexperiments.net"

# Run scripts (they inherit the environment)
./stack-03-swa-typescript-noauth.sh
```

**Automated setup:**

```nushell
# Interactive setup (auto-detects resource group)
source setup-env.nu

# Or use the exported function
overlay use setup-env.nu
setup

# Then run scripts
./stack-03-swa-typescript-noauth.sh
```

**Temporary scope with with-env:**

```nushell
with-env {
  RESOURCE_GROUP: "rg-subnet-calc"
  LOCATION: "uksouth"
  CUSTOM_DOMAIN: "publiccloudexperiments.net"
} {
  ./stack-03-swa-typescript-noauth.sh
}
```

**Inline environment variables:**

```nushell
RESOURCE_GROUP="rg-subnet-calc" LOCATION="uksouth" ./stack-03-swa-typescript-noauth.sh
```

### PowerShell

```powershell
# Set environment variables
$env:RESOURCE_GROUP = "rg-subnet-calc"
$env:LOCATION = "uksouth"
$env:CUSTOM_DOMAIN = "publiccloudexperiments.net"

# Run scripts using bash/sh
bash ./stack-03-swa-typescript-noauth.sh
```

### Fish

```fish
# Set environment variables
set -x RESOURCE_GROUP "rg-subnet-calc"
set -x LOCATION "uksouth"
set -x CUSTOM_DOMAIN "publiccloudexperiments.net"

# Run scripts (they inherit the environment)
./stack-03-swa-typescript-noauth.sh
```

## Script Numbering Convention

- **0x** - Static Web App scripts (00: create)
- **1x** - Function App and VNet scripts
- 10: Function App (Consumption)
- 11-14: VNet Integration (Phase 2)
- **2x** - Deployment scripts (20-22: direct, 23: APIM mode)
- **3x** - API Management scripts (30-32: APIM setup)
- **4x** - Custom Domains (Phase 1, future)
- **5x** - Private Endpoints (Phase 3, future)
- **9x** - Cleanup scripts (99: delete all)

## Auto-Detection and Smart Defaults

All scripts now include intelligent auto-detection to work seamlessly in sandbox environments (like Pluralsight) or when you have multiple resources.

**How it works:**

1. **0 resources found** - Error with helpful guidance on which script to run first
2. **1 resource found** - Auto-detect and prompt "Use this? (Y/n)" (defaults to yes)
3. **2+ resources found** - Behavior depends on resource type:
   - **Expensive resources** (APIM, App Service Plans): REFUSE with cost warnings
   - **Cheap resources** (Function Apps, VNets): LIST and prompt to select
   - **Configuration scripts**: LIST and prompt to select

**Examples:**

```bash
# Run without any environment variables - scripts auto-detect everything
./00-static-web-app.sh
# Auto-detects: RESOURCE_GROUP (if only 1 exists)
# Checks for: Existing Static Web Apps
# Behavior: Refuses to create when 2+ exist (expensive/one-per-app)

./10-function-app.sh
# Auto-detects: RESOURCE_GROUP
# Checks for: Existing Function Apps
# Behavior: Allows multiple with educational message

./21-deploy-function.sh
# Auto-detects: RESOURCE_GROUP, FUNCTION_APP_NAME
# Lists all Function Apps if 2+ exist and prompts for selection

./30-apim-instance.sh
# Auto-detects: RESOURCE_GROUP, PUBLISHER_EMAIL
# Checks for: Existing APIM instances
# Behavior: Refuses to create when 2+ exist ($60/month each!)
```

**You can still override any value:**

```bash
RESOURCE_GROUP="my-rg" FUNCTION_APP_NAME="my-func" ./21-deploy-function.sh
```

**Benefits:**

- Works out-of-the-box in Pluralsight sandbox (single resource group)
- Never fails cryptically - always provides helpful next steps
- Prevents expensive mistakes (refuses multiple App Service Plans with cost warning)
- Educational - explains why multiple resources may or may not be normal

## Quick Start

### 1. Create Infrastructure

```bash
# Set your resource group (or use default: rg-subnet-calc)
export RESOURCE_GROUP="1-xxxxx-playground-sandbox" # For Pluralsight sandbox
# or
export RESOURCE_GROUP="rg-subnet-calc" # For your own subscription

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
export RESOURCE_GROUP="1-xxxxx-playground-sandbox" # For Pluralsight sandbox
# or
export RESOURCE_GROUP="rg-subnet-calc" # For your own subscription

# Create Static Web App (Free SKU)
./00-static-web-app.sh

# Create Function App (Consumption plan)
./10-function-app.sh

# Create API Management (Developer SKU - takes ~37 minutes!)
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

## Quick Start - VNet Integration (Phase 2)

Deploy Function App with VNet integration for private networking capabilities. Requires App Service Plan instead of Consumption.

**See detailed guide:** [docs/SANDBOX-TESTING-GUIDE.md](docs/SANDBOX-TESTING-GUIDE.md)

**Architecture:**

```text
┌─────────────────────────────────────┐
│ Azure Static Web App (Free SKU) │
└──────────────┬──────────────────────┘
 │ HTTPS
┌──────────────▼──────────────────────┐
│ Azure Function App (App Service) │
│ - Runs on App Service Plan B1 │
│ - VNet Integration enabled │
│ - All traffic routed through VNet │
└──────────────┬──────────────────────┘
 │
┌──────────────▼──────────────────────┐
│ Azure Virtual Network │
│ - Function integration subnet │
│ - Private endpoints subnet │
│ - NSG with outbound rules │
└─────────────────────────────────────┘
```

**Cost:** ~$0.07 for 4-hour Pluralsight sandbox (B1 App Service Plan)

### 1. Create Infrastructure

```bash
# Set resource group
export RESOURCE_GROUP="1-xxxxx-playground-sandbox"

# Create VNet with subnets (10.0.0.0/16)
./11-create-vnet-infrastructure.sh

# Create App Service Plan B1 (Basic tier)
PLAN_SKU=B1 ./12-create-app-service-plan.sh

# Create Function App on App Service Plan
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./13-create-function-app-on-app-service-plan.sh
```

### 2. Enable VNet Integration

```bash
# Check current status (read-only)
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh --check

# Enable VNet integration
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh

# Verify integration (read-only)
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh --check
```

### 3. Deploy and Test

```bash
# Deploy Function code
RESOURCE_GROUP="$RESOURCE_GROUP" \
FUNCTION_APP_NAME="func-subnet-calc-asp" \
DISABLE_AUTH=true \
./21-deploy-function.sh

# Test API
curl https://func-subnet-calc-asp.azurewebsites.net/api/v1/health

# Deploy frontend
RESOURCE_GROUP="$RESOURCE_GROUP" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
API_URL="https://func-subnet-calc-asp.azurewebsites.net" \
./20-deploy-frontend.sh
```

### 4. Verify VNet Integration

```bash
# Check integration status
az functionapp vnet-integration list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP

# Check route-all setting
az functionapp config appsettings list \
 --name func-subnet-calc-asp \
 --resource-group $RESOURCE_GROUP \
 --query "[?name=='WEBSITE_VNET_ROUTE_ALL']"
```

**Benefits:**

- Access private resources in VNet (databases, VMs, etc.)
- Route all outbound traffic through VNet
- Always-on (no cold starts)
- Predictable costs

**Documentation:**

- [IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md) - Master plan for all phases
- [PHASE-2-VNET-INTEGRATION.md](docs/PHASE-2-VNET-INTEGRATION.md) - Detailed Phase 2 specs
- [SANDBOX-TESTING-GUIDE.md](docs/SANDBOX-TESTING-GUIDE.md) - Step-by-step sandbox testing

## Production Deployment Stacks

Complete end-to-end stacks for permanent Azure deployments with custom domain support.

**[Complete Production Guide](docs/PRODUCTION-DEPLOYMENT.md)** - Comprehensive deployment documentation
**[DNS Configuration Guide](docs/DNS-CONFIGURATION.md)** - Custom domain setup with Cloudflare

### Configuration

All stack scripts use these defaults (override via environment variables):

```bash
# Default location
export LOCATION="uksouth"  # UK South region

# Custom domain (configure your own)
export CUSTOM_DOMAIN="publiccloudexperiments.net"  # Change to your domain

# Resource naming
export RESOURCE_GROUP="rg-subnet-calc-prod"  # Or auto-detected
```

### Stack 0: Storage Static Website

**What**: Classic static website hosting on Azure Storage

**Cost**: ~$0.05/month

```bash
# Create storage with static website
./05-static-website-storage.sh

# Deploy static HTML frontend
SUBDOMAIN="static" ./25-deploy-static-website-storage.sh
```

**URL**: `https://static.publiccloudexperiments.net` (after DNS configuration)

**DNS**: CNAME `static` → `<storage>.z33.web.core.windows.net`

### Stack 3: SWA TypeScript (No Auth)

**What**: Modern TypeScript SPA with public API access

**Cost**: ~$0/month (Free tier SWA + Consumption Function)

```bash
# Deploy complete stack
SUBDOMAIN="noauth" ./stack-03-swa-typescript-noauth.sh
```

**URLs**:

- Frontend: `https://noauth.publiccloudexperiments.net`
- API: Auto-deployed Function App

**DNS**: CNAME `noauth` → `<swa>.azurestaticapps.net`

**Use Case**: Public APIs, demos, testing

### Stack 4: SWA TypeScript (JWT Auth)

**What**: Modern TypeScript SPA with JWT authentication

**Cost**: ~$0/month (Free tier SWA + Consumption Function)

```bash
# Deploy complete stack
SUBDOMAIN="jwt" \
JWT_USERNAME="demo" \
JWT_PASSWORD="your-secure-password" \
./stack-04-swa-typescript-jwt.sh
```

**URLs**:

- Frontend: `https://jwt.publiccloudexperiments.net`
- API: Auto-deployed Function App with JWT validation

**DNS**: CNAME `jwt` → `<swa>.azurestaticapps.net`

**Use Case**: Custom authentication, user management

**Login**: Username/password set during deployment

### Stack 5: SWA TypeScript (Entra ID)

**What**: Modern TypeScript SPA with enterprise SSO

**Cost**: ~$0/month (Free tier SWA + Consumption Function)

**Prerequisites**: Entra ID App Registration (see [PRODUCTION-DEPLOYMENT.md](docs/PRODUCTION-DEPLOYMENT.md#entra-id-setup))

```bash
# Deploy complete stack
SUBDOMAIN="entraid" \
AZURE_CLIENT_ID="<your-client-id>" \
AZURE_CLIENT_SECRET="<your-client-secret>" \
./stack-05-swa-typescript-entraid.sh
```

**URLs**:

- Frontend: `https://entraid.publiccloudexperiments.net`
- API: Auto-deployed Function App (no auth, SWA handles)

**DNS**: CNAME `entraid` → `<swa>.azurestaticapps.net`

**Use Case**: Enterprise SSO, Microsoft 365 integration

**Security**: Platform auth with opaque HttpOnly cookies (XSS/CSRF protected)

### Stack 6: Flask App Service

**What**: Server-side rendered Flask application

**Cost**: ~$13/month (App Service Plan B1)

```bash
# Deploy complete stack
SUBDOMAIN="flask" ./stack-06-flask-appservice.sh
```

**URLs**:

- Frontend: `https://flask.publiccloudexperiments.net`
- API: Auto-deployed Function App with JWT

**DNS**: CNAME `flask` → `<appservice>.azurewebsites.net`

**Use Case**: Traditional web apps, server-side rendering

**Authentication**: JWT handled server-side (tokens not visible to browser)

### Cost Summary

| Stack | Resources | Monthly Cost | Notes |
|-------|-----------|--------------|-------|
| **Storage** | Storage Account | ~$0.05 | Static website only |
| **Stack 3** | SWA + Function | ~$0.00 | Free tiers |
| **Stack 4** | SWA + Function | ~$0.00 | Shared Function with Stack 3 |
| **Stack 5** | SWA + Function | ~$0.00 | Shared Function with Stack 3/4 |
| **Stack 6** | App Service Plan B1 | ~$13.00 | Runs 24/7, shares with others |
| **Total** | | **~$13.05/month** | All 6 stacks |

**Cost Optimization**: Skip Stack 6 (Flask) for serverless-only deployment (~$0.05/month total)

### Comparison Matrix

| Feature | Stack 0 | Stack 3 | Stack 4 | Stack 5 | Stack 6 |
|---------|---------|---------|---------|---------|---------|
| **Hosting** | Storage | SWA | SWA | SWA | App Service |
| **Frontend** | HTML/JS | TypeScript | TypeScript | TypeScript | Flask |
| **Rendering** | Client | Client | Client | Client | Server |
| **Auth Method** | None | None | JWT (App) | Entra ID (Platform) | JWT (Server) |
| **Token Visibility** | N/A | N/A | Visible in browser | Opaque cookies | Server-side only |
| **XSS Protection** | N/A | None | None | HttpOnly cookies | Server-side |
| **CSRF Protection** | N/A | Manual | Manual | SameSite cookies | Manual |
| **Cold Start** | None | Possible | Possible | Possible | None (Always On) |
| **Cost** | ~$0.05 | ~$0 | ~$0 | ~$0 | ~$13 |
| **Use Case** | Simple sites | Public APIs | Custom auth | Enterprise SSO | Traditional apps |

### Quick Start - All Stacks

```bash
# Set environment
export RESOURCE_GROUP="rg-subnet-calc-prod"
export LOCATION="uksouth"
export CUSTOM_DOMAIN="publiccloudexperiments.net"

# Deploy all stacks
./stack-03-swa-typescript-noauth.sh
./stack-04-swa-typescript-jwt.sh
./stack-05-swa-typescript-entraid.sh  # Requires Entra ID setup
./stack-06-flask-appservice.sh

# Also deploy storage static website
./05-static-website-storage.sh
./25-deploy-static-website-storage.sh

# Configure DNS (see DNS-CONFIGURATION.md)
# Add CNAME records in Cloudflare for each subdomain

# Configure custom domains on Azure resources
# (After DNS propagation - see PRODUCTION-DEPLOYMENT.md)
```

## Complete Working Example - APIM in Pluralsight Sandbox

This is a **complete, tested, working example** from a real Pluralsight sandbox deployment. All commands have been verified and work correctly.

### Timing Breakdown

| Step                  | Duration    | Notes                            |
| --------------------- | ----------- | -------------------------------- |
| Environment setup     | 1 min       | Auto-detects sandbox             |
| Function App creation | 2 min       | Consumption plan                 |
| Function deployment   | 3 min       | Python FastAPI                   |
| **APIM provisioning** | **37 min**  | Developer SKU (eastus)           |
| APIM configuration    | 2 min       | API import + policies            |
| **Total**             | **~44 min** | Well within 4-hour sandbox limit |

### Step 1: Environment Setup (1 minute)

```bash
# Run setup script (auto-detects sandbox)
./setup-env.sh

# Copy and paste the export commands it provides:
export RESOURCE_GROUP='1-5a32dcec-playground-sandbox'
export PUBLISHER_EMAIL='cloud_user_p_ec7faff6@realhandsonlabs.com'
```

**What setup-env.sh does:**

- Detects Pluralsight sandbox automatically (single resource group pattern)
- Gets your Azure account email for APIM publisher
- Validates resource group exists
- Provides ready-to-use export commands

### Step 2: Create Function App (2 minutes)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
PUBLISHER_EMAIL='cloud_user_p_ec7faff6@realhandsonlabs.com' \
./10-function-app.sh

# Output shows:
# - Storage account: stsubnetcalc51606
# - Function App: func-subnet-calc-51606
# - URL: https://func-subnet-calc-51606.azurewebsites.net
```

### Step 3: Deploy Function API (3 minutes)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
FUNCTION_APP_NAME='func-subnet-calc-51606' \
DISABLE_AUTH=true \
./21-deploy-function.sh

# Test the Function App directly:
curl https://func-subnet-calc-51606.azurewebsites.net/api/v1/health
# {"status":"healthy","service":"Subnet Calculator API (Azure Function)","version":"1.0.0"}
```

### Step 4: Create APIM Instance (37 minutes)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
PUBLISHER_EMAIL='cloud_user_p_ec7faff6@realhandsonlabs.com' \
./30-apim-instance.sh

# IMPORTANT: This takes ~37 minutes!
# - Script polls every 30 seconds
# - Status: Activating → Succeeded
# - You can safely cancel (Ctrl+C) and check status later:

az apim list --resource-group '1-5a32dcec-playground-sandbox' \
 --query "[].{Name:name, State:provisioningState}" -o table

# Output when complete:
# - APIM Name: apim-subnet-calc-47022
# - Gateway URL: https://apim-subnet-calc-47022.azure-api.net
# - Status: Succeeded
```

**While waiting for APIM:**

- Take a coffee break
- Read the [APIM policies documentation](policies/README.md)
- Explore the Azure Portal
- Check other sandbox resources

### Step 5: Configure APIM Backend (2 minutes)

```bash
# Import Function App API into APIM
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
APIM_NAME='apim-subnet-calc-47022' \
FUNCTION_APP_NAME='func-subnet-calc-51606' \
./31-apim-backend.sh

# What this does:
# - Downloads OpenAPI spec from Function App
# - Imports API into APIM (creates operations)
# - Sets backend URL to Function App
# - Configures path: /subnet-calc

# Output:
# OpenAPI spec downloaded
# API imported from OpenAPI spec
# API Path: /subnet-calc
# Backend: https://func-subnet-calc-51606.azurewebsites.net
# APIM Gateway: https://apim-subnet-calc-47022.azure-api.net/subnet-calc
```

### Step 6: Apply APIM Policies (1 minute)

Option A: No Authentication (for testing)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
APIM_NAME='apim-subnet-calc-47022' \
AUTH_MODE='none' \
./32-apim-policies.sh

# What this does:
# - Applies no-auth policy (rate limiting only: 100 req/min)
# - Configures CORS for frontend access
# - Disables subscription requirement
# - Enables open public access

# Output:
# Policy applied successfully
# Subscription requirement disabled
# Authentication: None (open access)
```

Option B: Subscription Key Authentication (recommended for sandbox)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' \
APIM_NAME='apim-subnet-calc-47022' \
AUTH_MODE='subscription' \
./32-apim-policies.sh

# What this does:
# - Requires Ocp-Apim-Subscription-Key header
# - Creates subscription: subnet-calc-subscription
# - Returns primary and secondary keys
# - Enables rate limiting: 100 req/min

# Output:
# Policy applied successfully
# Subscription requirement enabled
# Subscription created
# Primary Key: abc123...xyz
# Secondary Key: def456...uvw
```

### Step 7: Test the Deployment

**Test APIM health endpoint (no auth mode):**

```bash
curl https://apim-subnet-calc-47022.azure-api.net/subnet-calc/api/v1/health
# {"status":"healthy","service":"Subnet Calculator API (Azure Function)","version":"1.0.0"}
```

**Test with subscription key (subscription mode):**

```bash
curl -H "Ocp-Apim-Subscription-Key: abc123...xyz" \
 https://apim-subnet-calc-47022.azure-api.net/subnet-calc/api/v1/health
```

**Test rate limiting:**

```bash
# Run 150 requests (exceeds 100/min limit)
for i in {1..150}; do
 curl -s https://apim-subnet-calc-47022.azure-api.net/subnet-calc/api/v1/health
 sleep 0.1
done
# After 100 requests: {"statusCode": 429, "message": "Rate limit is exceeded..."}
```

### Step 8: Cleanup (When Done)

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox' ./99-cleanup.sh

# What this deletes:
# - APIM instance (background deletion, ~15 min)
# - Function App
# - Storage Account
# - Static Web App (if created)
# - VNet and NSG (if created)
# - App Service Plan (if created)
#
# Keeps: Resource group (sandbox won't let you delete it anyway)
```

### Key Learnings from Sandbox Testing

1. **APIM is faster than documented**: 37 minutes vs 45 minutes (17% faster in eastus)
1. **setup-env.sh auto-detects sandboxes**: No manual configuration needed
1. **Scripts use `az rest` for policies**: Azure CLI doesn't have `az apim api policy` commands
1. **Subscription requirement must be explicitly disabled**: Default is enabled after API import
1. **Total deployment fits easily in 4-hour sandbox**: ~44 minutes including APIM

### Common Sandbox Issues

**Issue**: `az apim api policy create` command not found
**Solution**: Fixed in script 32 - now uses `az rest` with Management API

**Issue**: API returns 401 even with no-auth policy
**Solution**: Must explicitly disable subscription requirement with `az apim api update --subscription-required false`

**Issue**: APIM provisioning seems stuck at "Activating"
**Solution**: This is normal! Takes 30-40 minutes. Be patient.

### Real Variables from Tested Deployment

These are actual values from the example above (sanitized for security):

```bash
RESOURCE_GROUP='1-5a32dcec-playground-sandbox'
PUBLISHER_EMAIL='cloud_user_p_ec7faff6@realhandsonlabs.com'
SUBSCRIPTION_ID='2213e8b1-dbc7-4d54-8aff-b5e315df5e5b'
LOCATION='eastus'

STORAGE_ACCOUNT='stsubnetcalc51606'
FUNCTION_APP_NAME='func-subnet-calc-51606'
APIM_NAME='apim-subnet-calc-47022'

FUNCTION_URL='https://func-subnet-calc-51606.azurewebsites.net'
APIM_GATEWAY='https://apim-subnet-calc-47022.azure-api.net'
API_PATH='subnet-calc'
FULL_API_URL='https://apim-subnet-calc-47022.azure-api.net/subnet-calc'
```

### Cost Summary for 4-Hour Sandbox

| Resource        | SKU          | 4-Hour Cost                  |
| --------------- | ------------ | ---------------------------- |
| Function App    | Consumption  | $0.00 (free tier)            |
| Storage Account | Standard LRS | $0.00 (minimal)              |
| APIM            | Developer    | $0.00 (prorated: ~$0.12/day) |
| **Total**       |              | **~$0.02**                   |

**Note**: Developer SKU is approximately $60/month, which is $0.50/hour or $0.02 for 4 hours. Actual charges may vary.

## Scripts

### 00-static-web-app.sh

Creates an Azure Static Web App for hosting the frontend.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export LOCATION="eastus" # Azure region (auto-detected if RG exists)
export STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA name
export STATIC_WEB_APP_SKU="Free" # SKU (Free or Standard)
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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export LOCATION="eastus" # Azure region (auto-detected if RG exists)
export FUNCTION_APP_NAME="func-subnet-calc" # Function App name
export STORAGE_ACCOUNT_NAME="stsubnetcalc123456" # Storage (auto-generated if not set)
export PYTHON_VERSION="3.11" # Python runtime version
```

**Usage:**

```bash
./10-function-app.sh
```

**Output:**

- Function App URL
- CORS configured for all origins
- HTTPS only enabled

### 11-create-vnet-infrastructure.sh

Creates Azure Virtual Network with subnets for Phase 2 VNet integration.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export LOCATION="eastus" # Azure region (auto-detected)
export VNET_NAME="vnet-subnet-calc" # VNet name
export VNET_ADDRESS_SPACE="10.0.0.0/16" # VNet CIDR
export SUBNET_FUNCTION_NAME="snet-function-integration" # Function subnet name
export SUBNET_FUNCTION_PREFIX="10.0.1.0/28" # Function subnet CIDR (16 addresses)
export SUBNET_PE_NAME="snet-private-endpoints" # Private Endpoints subnet name
export SUBNET_PE_PREFIX="10.0.2.0/28" # PE subnet CIDR (16 addresses)
export NSG_NAME="nsg-subnet-calc" # Network Security Group name
```

**Usage:**

```bash
./11-create-vnet-infrastructure.sh
```

**Output:**

- VNet with 10.0.0.0/16 address space
- Function integration subnet (10.0.1.0/28) with Microsoft.Web/serverFarms delegation
- Private Endpoints subnet (10.0.2.0/28) for future use
- NSG with outbound rules attached to Function subnet

**Cost:** $0 (VNets are free)

### 12-create-app-service-plan.sh

Creates App Service Plan for running Functions with VNet integration support.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export LOCATION="eastus" # Azure region (auto-detected)
export PLAN_NAME="plan-subnet-calc" # App Service Plan name
export PLAN_SKU="B1" # SKU (B1, B2, B3, S1, S2, S3, P1V2, etc.)
export PLAN_OS="Linux" # OS (Linux for Python Functions)
```

**SKU Options:**

- **B1** (~$13/month, ~$0.02/hour) - Basic tier, 1 vCPU, 1.75GB RAM, VNet integration
- **S1** (~$70/month, ~$0.10/hour) - Standard tier, 1 vCPU, 1.75GB RAM, VNet + auto-scale
- **P1V2** (~$80/month) - Premium v2, 1 vCPU, 3.5GB RAM, enhanced performance

**Usage:**

```bash
# Create B1 plan (lowest cost with VNet support)
PLAN_SKU=B1 ./12-create-app-service-plan.sh

# Create S1 plan (production with auto-scale)
PLAN_SKU=S1 ./12-create-app-service-plan.sh
```

**Output:**

- App Service Plan details (SKU, cores, RAM, OS)
- Cost estimates (hourly, monthly, 4-hour sandbox)

**Cost:** Starts immediately (~$0.02/hour for B1, ~$0.10/hour for S1)

### 13-create-function-app-on-app-service-plan.sh

Creates Azure Function App on an existing App Service Plan (not Consumption).

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc-asp" # Function App name (required)
export APP_SERVICE_PLAN="plan-subnet-calc" # App Service Plan name
export STORAGE_ACCOUNT="stsubnetcalcasp123" # Storage (auto-generated if not set)
export PYTHON_VERSION="3.11" # Python runtime version
```

**Usage:**

```bash
FUNCTION_APP_NAME="func-subnet-calc-asp" ./13-create-function-app-on-app-service-plan.sh
```

**Output:**

- Function App created on App Service Plan (not Consumption)
- Storage account created if needed
- URL: <https://func-subnet-calc-asp.azurewebsites.net>

**Cost:** No additional cost (uses existing App Service Plan capacity)

### 14-configure-function-vnet-integration.sh

Enables VNet integration on a Function App running on App Service Plan.

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc-asp" # Function App name (required)
export VNET_NAME="vnet-subnet-calc" # VNet name
export SUBNET_NAME="snet-function-integration" # Subnet name
export ROUTE_ALL_TRAFFIC="true" # Route all outbound via VNet
```

**Usage:**

```bash
# Check current status (read-only)
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh --check

# Enable VNet integration
FUNCTION_APP_NAME="func-subnet-calc-asp" \
./14-configure-function-vnet-integration.sh
```

**Modes:**

- **Normal mode** (no flags): Enables VNet integration, sets WEBSITE_VNET_ROUTE_ALL=1
- **Check mode** (`--check` flag): Read-only status report, shows current integration state

**Output:**

- VNet integration status (Connected/Not Connected)
- Connected VNet and subnet IDs
- WEBSITE_VNET_ROUTE_ALL setting
- Outbound IP addresses
- Function connectivity test

**Cost:** $0 (VNet integration is free with App Service Plan)

### 20-deploy-frontend.sh

Deploys a frontend to Azure Static Web App.

**Supported frontends:**

- `typescript` - TypeScript + Vite SPA (recommended)
- `static` - Static HTML + vanilla JavaScript
- `flask` - Not supported (requires server runtime)

**Configuration:**

```bash
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA name
export FRONTEND="typescript" # Frontend type
export API_URL="https://func-xyz.azurewebsites.net" # Optional: API URL
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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc" # Function App name
export DISABLE_AUTH="false" # Disable JWT auth (true/false)
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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export FUNCTION_APP_NAME="func-subnet-calc" # Function App name
export APIM_NAME="apim-subnet-calc" # APIM instance name
```

**Usage:**

```bash
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-12345" \
APIM_NAME="apim-subnet-calc-67890" \
./23-deploy-function-apim.sh
```

**What it does:**

1. Sets `AUTH_METHOD=apim` on Function App (trusts X-User-\* headers from APIM)
1. Gets APIM public IP addresses
1. Adds IP restrictions to Function App (only accepts APIM traffic)
1. Disables CORS on Function App (APIM handles it)
1. Deploys function code with remote build

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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export LOCATION="eastus" # Azure region (auto-detected if RG exists)
export APIM_NAME="apim-subnet-calc" # APIM name (auto-generated with random suffix if not set)
export APIM_SKU="Developer" # SKU (Developer, Basic, Standard, Consumption)
export PUBLISHER_EMAIL="your@email.com" # Required: Admin email
export PUBLISHER_NAME="Your Name" # Publisher name (defaults to email if not set)
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

- **Developer SKU**: ~37 minutes
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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export APIM_NAME="apim-subnet-calc" # APIM instance name
export FUNCTION_APP_NAME="func-subnet-calc" # Function App name
export API_PATH="subnet-calc" # API path in APIM gateway (default: subnet-calc)
export API_DISPLAY_NAME="Subnet Calculator API" # Display name in APIM portal
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
1. Imports API into APIM with all operations
1. Links APIM backend to Function App URL
1. Configures HTTPS protocol and subscription requirement

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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export APIM_NAME="apim-subnet-calc" # APIM instance name
export API_PATH="subnet-calc" # API path (must match 31-apim-backend.sh)
export AUTH_MODE="subscription" # Auth mode: none, subscription, jwt
export RATE_LIMIT="100" # Requests per minute (default: 100)
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

1. **subscription** - Subscription key authentication (recommended for sandbox)

- Requires `Ocp-Apim-Subscription-Key` header
- Rate limiting: 100 requests/minute per subscription
- CORS enabled for all origins
- Injects subscription ID as X-User-ID
- Script creates subscription and outputs keys

1. **jwt** - JWT token authentication (requires Entra ID)

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
export RESOURCE_GROUP="rg-subnet-calc" # Resource group name
export STATIC_WEB_APP_NAME="swa-subnet-calc" # SWA name
export FUNCTION_APP_NAME="func-subnet-calc" # Function App name
export DELETE_RG="false" # Delete RG (true/false)
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
./21-deploy-function.sh # Don't set DISABLE_AUTH=true

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
- **Header Injection**: Trusted X-User-\* headers from APIM to Function

**Authentication modes:**

1. **Subscription Key** (recommended for sandbox):

- Requires `Ocp-Apim-Subscription-Key` header
- Easy to test and manage
- Works in Pluralsight sandbox
- Suitable for API integrations

1. **JWT / Entra ID** (production SSO):

- Requires `Authorization: Bearer <token>` header
- Validates against Azure Entra ID
- Enterprise single sign-on
- **NOT supported in Pluralsight sandbox**

1. **Open Access** (development):

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

APIM Developer SKU takes ~37 minutes to provision. This is normal.

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
1. **Add Custom Domains** - Configure custom DNS
1. **Add Application Insights** - Telemetry and monitoring
1. **Add Terraform** - Infrastructure as Code version
1. **Upgrade to APIM** - Follow Option 2 for production-grade API gateway

### Option 2: API Management (Already Implemented)

The APIM deployment scripts (30-32, 23) provide:

- API gateway with rate limiting
- Multiple authentication modes (none, subscription, JWT)
- IP restrictions (Function App behind APIM)
- CORS handling at gateway level
- Header injection for user context

**Additional enhancements:**

1. **Add Custom Domains** - Configure custom DNS for APIM gateway
1. **Add Application Insights** - Telemetry, monitoring, and distributed tracing
1. **Add VNet Integration** - Private network for Function App (remove public access)
1. **Add Multiple Regions** - APIM multi-region deployment for HA
1. **Add Entra ID Integration** - Enable JWT authentication mode (not for sandbox)
1. **Add Terraform** - Infrastructure as Code version of APIM deployment

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
