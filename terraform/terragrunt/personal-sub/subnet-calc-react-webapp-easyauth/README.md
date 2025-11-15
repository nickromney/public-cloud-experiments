# Subnet Calculator React Web App (Easy Auth)

This stack now uses the same modular Terragrunt pattern as the `subnet-calc-react-easyauth-proxied` deployment. It provisions:

- Linux Function App (Python 3.11) hosted on its own Elastic Premium plan.
- Linux Web App (Node) hosting the React proxy with Azure AD Easy Auth enabled.
- Optional App Insights / Log Analytics integration (defaults to the shared workspace ID).
- Azure AD app registration wired in through the `web_apps.frontend.easy_auth.entra_app_key` relationship.

The backend keeps `AUTH_METHOD=jwt`, while the frontend signs users in via Easy Auth and forwards JWT credentials to the proxy for local dev parity.

## Configuration Highlights

All inputs are expressed in `terraform.tfvars`:

- `service_plans` – define or reference the Web + Function plans.
- `storage_accounts.funcapp` – optional dedicated storage for the Function App.
- `application_insights` / `shared_log_analytics_workspace_id` – choose whether to create a local Insights instance or reuse the shared one.
- `entra_id_apps.frontend` – registers the SPA so Easy Auth can issue tokens.
- `function_apps.api` – runtime settings, CORS list, and JWT configuration for FastAPI.
- `web_apps.frontend` – Node runtime, startup command, runtime config, and Easy Auth wiring.

## Deploy

```bash
cd terraform/terragrunt/personal-sub/subnet-calc-react-webapp-easyauth
terragrunt run -- init
terragrunt run -- plan
terragrunt run -- apply
```

After Terraform:

1. Publish the Function App zip or container (`scripts/22-deploy-function-zip.sh`).
2. Deploy the React build (CI, `az webapp deploy`, etc.). Easy Auth enforces Azure AD logins and injects headers into the proxy.

## Notes

- Stage overlays have been removed. Create ad-hoc overrides by copying `terraform.tfvars` if you want experimental settings.
- For a managed-identity proxy that forwards Easy Auth headers to the backend, compare with `subnet-calc-react-easyauth-proxied`.
