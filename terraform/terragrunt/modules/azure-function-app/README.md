# Azure Function App Module

Terraform module for deploying Linux Azure Function App with storage account and service plan.

## Features

- Linux Function App with Python, Node.js, or .NET runtime
- System-assigned managed identity (always enabled)
- App Service Plan management
- Storage account for function app state
- Configurable SKU and runtime version
- CORS configuration
- Security best practices (HTTPS only, TLS 1.2, FTPS disabled)

## Usage

### Python Function App

```hcl
module "function_app" {
  source = "../../modules/azure-function-app"

  name                = "func-myapp-api"
  resource_group_name = azurerm_resource_group.this.name
  location            = "uksouth"

  plan_name = "plan-myapp-func"
  plan_sku  = "EP1"

  runtime         = "python"
  runtime_version = "3.11"

  cors_allowed_origins = [
    "https://web-myapp.azurewebsites.net",
    "http://localhost:5173"
  ]

  app_settings = {
    AUTH_METHOD  = "jwt"
    JWT_SECRET_KEY = "your-secret-key"
  }

  tags = {
    environment = "dev"
    managed_by  = "terragrunt"
  }
}
```

### Node.js Function App

```hcl
module "function_app" {
  source = "../../modules/azure-function-app"

  name                = "func-myapp-api"
  resource_group_name = azurerm_resource_group.this.name
  location            = "uksouth"

  plan_name = "plan-myapp-func"
  plan_sku  = "Y1" # Consumption plan

  runtime         = "node"
  runtime_version = "18"

  public_network_access_enabled = true

  cors_allowed_origins = ["*"]

  tags = {
    environment = "dev"
    managed_by  = "terragrunt"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Function App | string | n/a | yes |
| resource_group_name | Name of the resource group | string | n/a | yes |
| location | Azure region | string | n/a | yes |
| plan_name | Name of the App Service Plan | string | n/a | yes |
| plan_sku | SKU for the App Service Plan | string | n/a | yes |
| runtime | Function App runtime | string | n/a | yes |
| runtime_version | Runtime version | string | n/a | yes |
| storage_account_name | Storage account name | string | "" | no |
| public_network_access_enabled | Enable public network access | bool | true | no |
| cors_allowed_origins | List of allowed CORS origins | list(string) | ["*"] | no |
| cors_support_credentials | Enable CORS credentials support | bool | false | no |
| app_settings | Application settings | map(string) | {} | no |
| tags | Tags to apply | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| function_app_id | The ID of the Function App |
| function_app_name | The name of the Function App |
| function_app_hostname | Default hostname of the Function App |
| function_app_url | HTTPS URL for the Function App |
| function_app_identity_principal_id | Principal ID of managed identity |
| function_app_identity_tenant_id | Tenant ID of managed identity |
| service_plan_id | The ID of the App Service Plan |
| service_plan_name | The name of the App Service Plan |
| storage_account_id | The ID of the storage account |
| storage_account_name | The name of the storage account |

## Supported Runtimes

- **Python**: 3.8, 3.9, 3.10, 3.11, 3.12
- **Node.js**: 14, 16, 18, 20
- **.NET Isolated**: 6.0, 7.0, 8.0

## Supported SKUs

- **Consumption**: Y1
- **Elastic Premium**: EP1, EP2, EP3
- **App Service Plan**: B1-B3, S1-S3, P1v2-P3v3

## Security Features

- HTTPS only enabled
- TLS 1.2 minimum
- FTPS disabled
- HTTP/2 enabled
- System-assigned managed identity always enabled
- Storage account with HTTPS only and TLS 1.2
