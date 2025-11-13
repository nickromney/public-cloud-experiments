# Subnet Calculator React Web App (Easy Auth Proxy)

This Terragrunt stack provisions the “App Service + Function (proxied)” experiment. It is the companion to `subnet-calc-react-easyauth-e2e`, but demonstrates how the Azure Web App can keep the backend origin private by proxying all `/api/*` calls via `frontend-react/server.js`.

It deploys:

- An **App Service plan** plus a **Linux Web App** that hosts the `subnet-calculator/frontend-react` build.
- A dedicated **Function App** (Linux, Premium plan) for `subnet-calculator/api-fastapi-azure-function`.
- **Easy Auth (Azure AD)** on both the Web App and Function App. Visitors authenticate once at the Web App and their Easy Auth headers are forwarded to the backend by the proxy middleware.

Unlike the E2E stack, this deployment sets `PROXY_API_URL` (and leaves `API_BASE_URL` empty) so the Node runtime forwards API calls on behalf of the browser. The backend hostname never appears in DevTools, which mirrors how Azure Static Web Apps “linked” Function Apps behave.

## Prerequisites

1. Azure credentials exported for Terragrunt (`ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, backend storage envs).
2. Default region: UK South. Set `PERSONAL_SUB_REGION=uksouth` (already assumed) if you need to override for troubleshooting.
3. Resource group naming follows CAF: this stack uses `rg-subnet-calc`.
4. An Azure AD App Registration with redirect URIs for both the Web App and Function App (`/.auth/login/aad/callback`).
5. Optional: override the storage account or plan names if these collide with existing resources.

## Configuration

1. Copy `terraform.tfvars.example` to `terraform.tfvars` (already provided in this repo).
2. Update the following blocks:
   - `service_plans.shared`: adjust SKU/size if you need a cheaper or bigger plan.
   - `function_apps.api`: confirm the CORS origins and any custom app settings required by FastAPI.
   - `web_apps.frontend.app_settings`: keep `API_BASE_URL = ""`, set `PROXY_API_URL` to the deployed Function App host, and set both `AUTH_METHOD`/`AUTH_MODE = "easyauth"` so the SPA’s runtime config matches.
3. (Optional) If you lock down the Function App (private endpoints, APIM, App Gateway), update `PROXY_API_URL` to the new internal DNS name and ensure the Web App has outbound access.

## Usage

```bash
cd terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-proxied
export PERSONAL_SUB_REGION=uksouth   # optional if already default
terragrunt init
terragrunt plan
terragrunt apply
```

Key outputs:

- `web_app_url` – primary URL for the React frontend.
- `web_app_login_url` – Easy Auth endpoint for smoke tests (`/.auth/login/aad`).
- `function_app_api_base_url` – value consumed by `PROXY_API_URL`.

After `terragrunt apply`, deploy the React build with `make web-app-deploy` (or `az webapp deploy`) and publish the FastAPI Azure Function ZIP using `make function-app-deploy` or `scripts/22-deploy-function-zip.sh`. Easy Auth enforces Azure AD logins, and because the Web App owns the outbound call, the Function App can sit behind APIM or App Gateway without exposing its hostname to end users.

### Stage Overlays & Toggle Workflow

The `stages/` directory provides layered configuration files for progressive infrastructure deployment:

- `stages/100-identity.tfvars` – adds the user-assigned managed identity plus Entra ID registration.
- `stages/200-storage.tfvars` / `300-rbac.tfvars` – adds storage and RBAC for the Function App.
- `stages/400-function-app.tfvars` – provisions the Function App with Easy Auth.
- `stages/500-web-app.tfvars` – enables the Web App + proxy settings.
- `stages/000-all.tfvars` – complete stack blueprint.

Apply an overlay with standard Terragrunt syntax:

```bash
terragrunt plan -- -var-file=stages/500-web-app.tfvars
```

Copy or extend these overlays to document every environment's toggle set without editing `terraform.tfvars` directly.

For infrastructure re-use (BYO shared components, plans, storage), follow the same guidance documented in `subnet-calc-react-easyauth-e2e/README.md`. The modules are shared, so the override knobs work identically in this stack.
