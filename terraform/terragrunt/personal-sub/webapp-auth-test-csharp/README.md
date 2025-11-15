# C# .NET 9.0 Testing Stack for Azure Easy Auth with Managed Identity

This Terragrunt stack captures the current state of C# .NET 9.0 test applications deployed via Azure CLI. It serves as a baseline for testing Azure Easy Auth patterns with Managed Identity.

## Current State (Baseline)

This stack captures what was deployed via Azure CLI for version control **before** iterating on authentication:

- **Function App**: `func-csharp-test-f6fe93` - .NET 9.0 isolated worker
  - Endpoints: `/api/health`, `/api/test`
  - No authentication configured
  - Auto-created storage account: `stcsharptestf6fe93`

- **Web App**: `web-csharp-test-f6fe93` - ASP.NET Core minimal API
  - Endpoints: `/`, `/health`, `/test` (proxies to Function App)
  - System-assigned Managed Identity enabled
  - No Easy Auth configured yet

- **Shared Resources**: Uses existing App Service Plan `plan-subnetcalc-dev-easyauth-proxied`

## Purpose

This stack establishes a clean baseline for testing Easy Auth with Microsoft's preferred language (.NET) instead of Node.js/React. The proxying pattern works (Web App → Function App), and the infrastructure is now version-controlled.

## Future Iterations (Staged Approach)

Authentication will be added incrementally using tfvars stages:

1. **Stage 1**: Add JWT auth on Function App
2. **Stage 2**: Add Easy Auth on Web App
3. **Stage 3**: Configure Managed Identity for Web App → Function App authentication

## Prerequisites

1. Azure credentials exported for Terragrunt (`ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`)
2. Existing resource group: `rg-subnet-calc`
3. Existing App Service Plan: `plan-subnetcalc-dev-easyauth-proxied`
4. Region: UK South

## Deployment

```bash
# Initialize Terragrunt
cd terraform/terragrunt/personal-sub/webapp-auth-test-csharp
terragrunt init

# Plan (should show no changes - state equilibrium achieved)
terragrunt plan

# Apply only if making changes
terragrunt apply
```

## State Management

This stack was created by:

1. Deploying resources via Azure CLI
2. Creating Terraform configuration matching deployed state
3. Importing resources into Terraform state
4. Achieving state equilibrium (no changes on plan)

## C# Source Code

The C# applications are located in:

- Function App: `subnet-calculator/csharp-test/function-app/`
- Web App: `subnet-calculator/csharp-test/web-app/`
- Deployment scripts: `subnet-calculator/scripts/deploy-csharp-test.sh`

## Key Differences from React Stacks

- Uses .NET 9.0 (STS) instead of Node.js/React
- Minimal API pattern instead of Express/React
- No Easy Auth configured yet (baseline only)
- System-assigned MI on Web App (no User-Assigned Identities yet)
- No Application Insights (keeping it simple for testing)

## Critical Deployment Note

When deploying .NET apps to Azure App Service via CLI, you **must** manually configure the Stack in Azure Portal:

1. Configuration > General Settings
2. Set Stack: `.NET`
3. Set Major/Minor version: `.NET 9 (STS)`
4. Save and redeploy

See `subnet-calculator/csharp-test/DEPLOYMENT-NOTES.md` for full details on this critical issue.

## Testing

```bash
# Test Function App
curl https://func-csharp-test-f6fe93.azurewebsites.net/api/health
curl https://func-csharp-test-f6fe93.azurewebsites.net/api/test

# Test Web App (proxies to Function App)
curl https://web-csharp-test-f6fe93.azurewebsites.net/
curl https://web-csharp-test-f6fe93.azurewebsites.net/health
curl https://web-csharp-test-f6fe93.azurewebsites.net/test
```

## Resources

- Function App: `func-csharp-test-f6fe93`
- Web App: `web-csharp-test-f6fe93`
- Storage Account: `stcsharptestf6fe93` (auto-created by Azure)
- App Service Plan: `plan-subnetcalc-dev-easyauth-proxied` (shared, existing)
