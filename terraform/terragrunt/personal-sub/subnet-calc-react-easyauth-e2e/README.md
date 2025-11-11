# Subnet Calculator React Web App (Easy Auth)

This Terragrunt stack provisions the Azure infrastructure that previously lived in the `infrastructure/azure` bash scripts for the “App Service + Function” experiment. It deploys:

- An **App Service plan** plus a **Linux Web App** that hosts the `subnet-calculator/frontend-react` static build.
- A dedicated **Function App** plan + **Linux Function App** for `subnet-calculator/api-fastapi-azure-function`.
- **Easy Auth (Azure AD)** on the Web App using the guidance from `subnet-calculator/frontend-python-flask/EASY-AUTH-SETUP.md`.

The Web App exposes `API_BASE_URL` that points to the Function App’s `/api/v1` endpoints, mirroring Stack 1 (Static Web App + Azure Function) but on App Service with Easy Auth.

## Prerequisites

1. Azure credentials exported for Terragrunt (`ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, backend storage envs).
2. Default region: UK South. Set `PERSONAL_SUB_REGION=uksouth` (already assumed) if you need to override for troubleshooting.
3. Resource group naming follows CAF: this stack creates/uses `rg-subnet-calc`.
4. An Azure AD App Registration with a client secret. Use the same steps from `frontend-python-flask/EASY-AUTH-SETUP.md`.
5. Optional: a dedicated storage account name if you don’t want Terraform to derive one automatically.

## Configuration

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Update the following blocks:
   - `web_app.plan_sku`, `web_app.runtime_version` (Node version needed by the React build).
   - `web_app.easy_auth`: set `client_id`, `client_secret`, `issuer` (`https://login.microsoftonline.com/<tenant-id>/v2.0`), and any `allowed_audiences`.
   - `function_app.plan_sku`, `runtime = "python"`, `runtime_version = "3.11"`, and tighten `cors_allowed_origins` to the final hostname (replace `"*"`).
   - Add any custom `app_settings` required by the React SPA or FastAPI (for example `AUTH_METHOD=none` on the Function App).
3. (Optional) Override `web_app.api_base_url` if you need a different routing surface (default is the Function App host).

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

Terraform 1.8 + azurerm 4.0+ provider functions (`provider::azurerm::normalise_resource_id` and `provider::azurerm::parse_resource_id`) remove brittle `split("/")` parsing and ensure IDs are casing-correct before they are passed to the Azure APIs.
