# Azure Static Web App Module

Terragrunt module for managing Azure Static Web Apps with linked Function Apps.

## Features

- Static Web Apps with custom domains
- Function Apps (Linux) with custom hostnames
- App Service Plans
- Storage Accounts for Function Apps
- Managed identities support
- CORS configuration
- Custom domain bindings

## Usage

```hcl
static_web_apps = {
  "swa-subnet-calc-noauth" = {
    sku_tier                    = "Standard"
    custom_domains              = ["static-swa-no-auth.publiccloudexperiments.net"]
    staging_environment_policy  = "Enabled"
  }

  "swa-subnet-calc-entraid-linked" = {
    sku_tier       = "Standard"
    custom_domains = ["static-swa-entraid-linked.publiccloudexperiments.net"]
    linked_backend = {
      backend_resource_id = azurerm_linux_function_app.this["func-subnet-calc-entraid-linked"].id
      region              = "uksouth"
    }
  }
}

function_apps = {
  "func-subnet-calc-jwt" = {
    app_service_plan_id        = azurerm_service_plan.this["plan-consumption"].id
    storage_account_name       = azurerm_storage_account.this["stfuncjwt"].name
    storage_account_access_key = azurerm_storage_account.this["stfuncjwt"].primary_access_key

    site_config = {
      application_stack = {
        python_version = "3.11"
      }
      cors = {
        allowed_origins = ["https://static-swa-no-auth.publiccloudexperiments.net"]
      }
    }

    app_settings = {
      AUTH_METHOD = "jwt"
    }

    custom_hostnames = ["subnet-calc-fa-jwt-auth.publiccloudexperiments.net"]
  }
}
```

## Import Existing Resources

```bash
# Static Web Apps
terragrunt import 'azurerm_static_web_app.this["swa-subnet-calc-noauth"]' /subscriptions/.../resourceGroups/rg-subnet-calc/providers/Microsoft.Web/staticSites/swa-subnet-calc-noauth

# Function Apps
terragrunt import 'azurerm_linux_function_app.this["func-subnet-calc-jwt"]' /subscriptions/.../resourceGroups/rg-subnet-calc/providers/Microsoft.Web/sites/func-subnet-calc-jwt
```

## Outputs

- `static_web_app_ids` - Resource IDs of Static Web Apps
- `static_web_app_default_hostnames` - Default .azurestaticapps.net hostnames
- `function_app_ids` - Resource IDs of Function Apps
- `function_app_default_hostnames` - Default .azurewebsites.net hostnames
