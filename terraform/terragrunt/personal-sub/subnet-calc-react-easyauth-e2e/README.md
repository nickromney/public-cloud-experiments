# Subnet Calculator React Web App (Easy Auth Direct)

This Terragrunt stack provisions the Azure infrastructure that previously lived in the `infrastructure/azure` bash scripts for the “App Service + Function” experiment. It deploys:

- An **App Service plan** plus a **Linux Web App** that hosts the `subnet-calculator/frontend-react` static build.
- A dedicated **Function App** plan + **Linux Function App** for `subnet-calculator/api-fastapi-azure-function`.
- **Easy Auth (Azure AD)** on the Web App using the guidance from `subnet-calculator/frontend-python-flask/EASY-AUTH-SETUP.md`.

The Web App exposes `API_BASE_URL` that points to the Function App’s `/api/v1` endpoints, mirroring Stack 1 (Static Web App + Azure Function) but on App Service with Easy Auth. If you need to keep the backend hostname private, use the sibling stack `subnet-calc-react-easyauth-proxied`, which enables the Express proxy instead.

## Prerequisites

1. Azure credentials exported for Terragrunt (`ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, backend storage envs).
2. Default region: UK South. Set `PERSONAL_SUB_REGION=uksouth` (already assumed) if you need to override for troubleshooting.
3. Resource group naming follows CAF: this stack creates/uses `rg-subnet-calc`.
4. Azure AD permissions to create app registrations **and** grant delegated permissions (the stack now provisions separate frontend/API apps plus the delegated grant automatically).
5. Optional: a dedicated storage account name if you don’t want Terraform to derive one automatically.

## Configuration

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Update the following blocks:
   - `service_plans`, `storage_accounts`, and `user_assigned_identities` if you need different SKUs or BYO resources.
   - `entra_id_apps.frontend` and `.api` to align with your hostnames. The API app exposes the `api://...-api` Application ID URI plus the `user_impersonation` scope, while `entra_id_app_delegated_permissions` grants the frontend delegated access to that scope so `/.auth/refresh?resource=...` works without a proxy.
   - `function_apps.api`: confirm the `cors_allowed_origins`, `AUTH_METHOD = "azure_ad"`, and Easy Auth `entra_app_key = "api"`.
   - `web_apps.frontend`: keep `AUTH_METHOD = "easyauth"` and set `EASYAUTH_RESOURCE_ID` to the API Application ID URI (exposed above).
3. Set `API_BASE_URL` to the Function App host so the browser can call it directly. No proxy variables are used in this stack (see the `proxied` sibling stack if you need that behavior).

### Easy Auth token flow

The stack now models the recommended two-app pattern:

- **Frontend app registration** → used by the Web App’s Easy Auth handler. Users sign in here and the SPA calls `/.auth/refresh?resource=api://subnet-calculator-react-easyauth-e2e-api`.
- **API app registration** → used by the Function App’s Easy Auth handler and exposes the `user_impersonation` scope.
- **Delegated permission grant** → Terraform creates an `azuread_service_principal_delegated_permission_grant` so the frontend is pre-consented for the API scope. This lets Easy Auth mint a downstream token that the SPA forwards in `Authorization`/`X-ZUMO-AUTH` headers.

With that split, the Function App honors the same Easy Auth token the frontend received, so direct browser calls no longer return `401/403`.

> **Limitation**  
> As of November 2025 the App Service Easy Auth control plane does **not** expose the `loginParameters` setting, which means the platform cannot be instructed (via Terraform/ARM) to request `api://…/.default` scopes for frontends hosted on a different hostname. Without that extra scope the `/.auth/refresh` endpoint returns `403` and the browser cannot obtain a Function App access token, even though both Entra ID apps and delegated permissions exist. See [docs/AUTHENTICATION.md](../../../../subnet-calculator/docs/AUTHENTICATION.md) for the current workarounds (proxy stack, shared Easy Auth boundary, or application-level On-Behalf-Of flow). If you need tokens to flow today, deploy the `subnet-calc-react-easyauth-proxied` stack or front both services with APIM/App Gateway/Front Door.

## Usage

```bash
cd terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-e2e
export PERSONAL_SUB_REGION=uksouth   # optional if already default
terragrunt init
terragrunt plan
terragrunt apply
```

Key outputs:

- `web_app_url` – primary URL for the React frontend.
- `web_app_login_url` – Easy Auth endpoint for smoke tests (`/.auth/login/aad`).
- `function_app_api_base_url` – value injected into `API_BASE_URL`.

After `terragrunt apply`, deploy the React build with `az webapp up` or the existing GitHub Action, and publish the FastAPI Azure Function ZIP using `scripts/22-deploy-function-zip.sh` if desired. Easy Auth enforces Azure AD logins, and the Function App is reachable publicly (lock down via `cors_allowed_origins` or IP restrictions as needed).

### Post-Apply Make Targets

This directory now has a convenience `Makefile`:

```bash
cd terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-e2e
make function-app-deploy   # packages & deploys api-fastapi-azure-function
make web-app-deploy        # builds frontend-react and deploys to App Service
```

Both targets read resource names from `terragrunt output` (or honor `FUNCTION_APP_NAME`/`WEB_APP_NAME` overrides) and default to `rg-subnet-calc`. Ensure you are logged into Azure CLI before running them.

### Stage Overlays & Toggle Workflow

The `stages/` directory provides layered configuration files for progressive infrastructure deployment:

- `stages/100-minimal.tfvars` – minimal inputs to unblock non-interactive plans with basic settings.
- `stages/200-create-observability.tfvars` – flips `create_resource_group` and `observability.use_existing` so this stack can stand alone.
- `stages/300-byo-platform.tfvars` – demonstrates reusing App Service Plans, Storage Accounts, and shared Log Analytics Workspace.

Apply an overlay with standard Terragrunt syntax:

```bash
terragrunt plan -- -var-file=stages/200-create-observability.tfvars
```

Copy or extend these overlays to document every environment's toggle set without editing `terraform.tfvars` directly.

### Bring Your Own Platform Resources

Function Apps can now reference existing infrastructure instead of creating new resources:

```hcl
function_app = {
  name                        = "func-subnet-calc"
  existing_service_plan_id    = "/subscriptions/<sub>/resourceGroups/rg-platform/providers/Microsoft.Web/serverFarms/plan-platform-ep1"
  existing_storage_account_id = "/subscriptions/<sub>/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stplatformshared"
}
```

Reference the shared Log Analytics Workspace from `subnet-calc-shared-components`:

```hcl
observability = {
  use_existing                 = true
  existing_resource_group_name = "rg-subnet-calc-shared-dev"
  existing_log_analytics_name  = "log-subnetcalc-shared-dev"
  # Note: App Insights is created per-stack, not shared
}
```

**Minimum Requirements**: Terraform 1.8+ and azurerm 4.0+ are required for provider-defined functions used in the BYO pattern. The `provider::azurerm::normalise_resource_id` and `provider::azurerm::parse_resource_id` functions provide robust resource ID parsing, removing brittle `split("/")` approaches and ensuring IDs are casing-correct before they are passed to Azure APIs.
