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
stacks = {
  # Stack with JWT authentication
  "noauth" = {
    swa = {
      sku            = "Standard"
      custom_domain  = "static-swa-no-auth.publiccloudexperiments.net"
      network_access = "Enabled"
    }

    function_app = {
      plan_sku       = "FC1"  # Flex Consumption
      python_version = "3.11"
      auth_method    = "jwt"
      custom_domain  = "subnet-calc-fa-jwt-auth.publiccloudexperiments.net"

      app_settings = {
        JWT_ACCESS_TOKEN_EXPIRE_MINUTES = "30"
        JWT_ALGORITHM                   = "HS256"
      }
    }
  }

  # Stack with Entra ID authentication
  "entraid-linked" = {
    swa = {
      sku            = "Standard"
      custom_domain  = "static-swa-entraid-linked.publiccloudexperiments.net"
      network_access = "Enabled"
      # Note: auth_enabled and auth_provider fields are planned for future implementation
    }

    function_app = {
      plan_sku       = "FC1"
      python_version = "3.11"
      auth_method    = "swa"  # Receives X-MS-CLIENT-PRINCIPAL header from SWA
      custom_domain  = "subnet-calc-fa-entraid-linked.publiccloudexperiments.net"
    }
  }
}
```

## Import Existing Resources

**Important**: Use the logical stack key (e.g., `["noauth"]`), not the Azure resource name, as the Terraform resource key.

```bash
# Static Web Apps
terragrunt import 'azurerm_static_web_app.this["noauth"]' /subscriptions/.../resourceGroups/rg-subnet-calc/providers/Microsoft.Web/staticSites/swa-subnet-calc-noauth

# Function Apps
terragrunt import 'azurerm_linux_function_app.this["noauth"]' /subscriptions/.../resourceGroups/rg-subnet-calc/providers/Microsoft.Web/sites/func-subnet-calc-jwt
```

## Outputs

- `static_web_app_ids` - Resource IDs of Static Web Apps
- `static_web_app_default_hostnames` - Default .azurestaticapps.net hostnames
- `function_app_ids` - Resource IDs of Function Apps
- `function_app_default_hostnames` - Default .azurewebsites.net hostnames
