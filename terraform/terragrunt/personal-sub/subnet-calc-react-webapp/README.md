# Subnet Calculator React Web App (JWT)

This stack provisions the classic “React SPA + FastAPI Function App” experiment using the new map-based Terragrunt modules. It mirrors the patterns used in `subnet-calc-react-easyauth-proxied`:

- Dedicated App Service plans for the Function App and Web App (Linux).
- Optional creation of Log Analytics / Application Insights (or re-use via `shared_log_analytics_workspace_id`).
- Single `terraform.tfvars` drives everything: `service_plans`, `function_apps`, `web_apps`, and (when required) `storage_accounts` or `user_assigned_identities`.

Authentication remains JWT-only on the backend (no Easy Auth). The Web App injects `AUTH_METHOD=jwt`, `JWT_USERNAME`, and `JWT_PASSWORD` runtime config for the React proxy.

## Usage

```bash
cd terraform/terragrunt/personal-sub/subnet-calc-react-webapp
terragrunt run -- init
terragrunt run -- plan
terragrunt run -- apply
```

Key inputs live in `terraform.tfvars`:

- `service_plans` – define the Linux plans (or point at existing ones via Terragrunt’s dependency injection).
- `application_insights` – optionally create a dedicated App Insights instance (or rely on the shared workspace id).
- `function_apps.api` – runtime, storage, and JWT app settings for FastAPI.
- `web_apps.frontend` – Node runtime, startup command, and runtime config for the React proxy.

Because we now use the shared modules, there is no `stages/` overlay; create temporary overlays by copying `terraform.tfvars` if you need environment-specific overrides.

## Deploying Code

Infrastructure and app deployments remain separate:

1. `terragrunt run -- apply` creates/updates Azure resources.
2. Deploy the FastAPI ZIP (`scripts/22-deploy-function-zip.sh` or GitHub Actions) – the Function App expects to build dependencies in Azure, so keep `SCM_DO_BUILD_DURING_DEPLOYMENT=true`.
3. Deploy the React build (`subnet-calculator/frontend-react`) with `az webapp deploy` or the existing CI workflow. The runtime config (`AUTH_METHOD`, `API_BASE_URL`, etc.) is injected via environment variables from `terraform.tfvars`.

## Outputs

- `function_app_api_base_url` – feed into CI/CD or smoke tests.
- `web_app_url` – public entry point for the SPA.

For a variant that proxies Easy Auth headers and uses Managed Identity, see the `subnet-calc-react-easyauth-proxied` stack.
