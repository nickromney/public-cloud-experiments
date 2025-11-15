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

## Stage 500 – Easy Auth + Managed Identity Proxy (NEW)

`stages/500-jwt-easyauth.tfvars` introduces Azure AD Easy Auth and Managed Identity bindings without touching the baseline `terraform.tfvars`. It can be planned/applied (and rolled back) with:

```bash
terragrunt plan  -- -var-file=stages/500-jwt-easyauth.tfvars
terragrunt apply -- -var-file=stages/500-jwt-easyauth.tfvars
```

What the overlay does:

- Creates a user-assigned managed identity (`id-web-webapp-auth-test-csharp`) and assigns it to the Web App.
- Provisions two Entra ID app registrations (frontend + API) with the API exposing a `user_impersonation` scope and `API.Access` app role.
- Grants the Web App’s managed identity the `API.Access` app role so it can request tokens for the Function App via Managed Identity.
- Enables Easy Auth on the Function App (`Return401` for anonymous calls) and the Web App (interactive login via Azure AD).
- Configures App Insights (`appi-webapp-auth-test-csharp`) so both sites emit telemetry to the shared Log Analytics workspace.
- Sets new Web App app settings: `FUNCTION_APP_SCOPE`, `FUNCTION_APP_AUDIENCE`, `FUNCTION_APP_URL`, `EASYAUTH_RESOURCE_ID`, and `USE_MANAGED_IDENTITY`. The C# web app now reads these settings to request a token with `DefaultAzureCredential`.

With this stage applied:

- Direct calls to `https://func-csharp-test-f6fe93.azurewebsites.net/api/test` return `401` unless a valid JWT for `api://webapp-auth-test-csharp-api` is presented.
- Requests to `https://web-csharp-test-f6fe93.azurewebsites.net/test` redirect to Azure AD login, then succeed because the Web App proxy acquires a Managed Identity token for the Function App scope.
- Reverting to the unauthenticated baseline is as simple as running `terragrunt plan/apply` without the stage file; no resources are destroyed automatically.

## Local Testing with podman-compose

The .NET repos now ship Dockerfiles plus a compose definition for smoke tests without touching Azure:

```bash
cd subnet-calculator/csharp-test
podman-compose -f compose.yml up --build
```

Behavior:

- The Function App container listens on `http://localhost:7071` (no Easy Auth locally).
- The Web App container proxies `http://localhost:8085/test` to the Function App via `FUNCTION_APP_URL=http://function-app`.
- Managed Identity tokens are **not** requested locally—leave `FUNCTION_APP_SCOPE` unset and the service will log “No authentication - calling Function App directly”.

To reproduce Azure-like flows locally, hit the Web App endpoints:

```bash
curl http://localhost:8085/test | jq
curl http://localhost:7071/api/test | jq   # still open locally
```

When deploying to Azure with Stage 500 enabled, the Web App automatically receives `FUNCTION_APP_SCOPE=api://webapp-auth-test-csharp-api/.default`, so the proxy starts requesting Managed Identity tokens and Azure Easy Auth enforces JWTs.

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
2. Set Stack: .NET
3. Set Major/Minor version: .NET 9 (STS)
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
