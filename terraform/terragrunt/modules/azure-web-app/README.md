# Azure Web App Module

Terraform module for deploying Linux App Service (Web App) with system-assigned managed identity and optional Easy Auth V2.

## Features

- Linux App Service with Node.js runtime
- System-assigned managed identity (always enabled)
- App Service Plan management
- Optional Easy Auth V2 with managed identity support
- Configurable SKU and runtime version
- Security best practices (HTTPS only, TLS 1.2, FTPS disabled)

## Usage

### Basic Web App (No Authentication)

```hcl
module "web_app" {
  source = "../../modules/azure-web-app"

  name                = "web-myapp-dev"
  resource_group_name = azurerm_resource_group.this.name
  location            = "uksouth"

  plan_name = "plan-myapp-dev"
  plan_sku  = "B1"

  runtime_version = "20-lts"
  always_on       = true

  app_settings = {
    API_BASE_URL = "https://api.example.com"
    STACK_NAME   = "My App"
  }

  tags = {
    environment = "dev"
    managed_by  = "terragrunt"
  }
}
```

### Web App with Easy Auth (Managed Identity)

```hcl
module "web_app" {
  source = "../../modules/azure-web-app"

  name                = "web-myapp-prod"
  resource_group_name = azurerm_resource_group.this.name
  location            = "uksouth"

  plan_name = "plan-myapp-prod"
  plan_sku  = "P1v3"

  easy_auth = {
    enabled                  = true
    client_id                = "00000000-0000-0000-0000-000000000000"
    use_managed_identity     = true
    tenant_id                = "your-tenant-id"
    issuer                   = "https://login.microsoftonline.com/your-tenant-id/v2.0"
    allowed_audiences        = ["api://myapp"]
    unauthenticated_action   = "RedirectToLoginPage"
    token_store_enabled      = true
  }

  app_settings = {
    API_BASE_URL = "https://api.example.com"
  }

  tags = {
    environment = "prod"
    managed_by  = "terragrunt"
  }
}
```

## Easy Auth with Managed Identity

This module supports Easy Auth V2 using system-assigned managed identity instead of client secrets:

1. The Web App's managed identity authenticates to Entra ID
2. No client secrets required or stored
3. No Key Vault needed for secret management
4. More secure and easier to manage

### Prerequisites for Easy Auth

1. Create an Entra ID App Registration
2. Note the Application (client) ID
3. Configure redirect URIs in the app registration
4. No client secret needed when using managed identity

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Web App | string | n/a | yes |
| resource_group_name | Name of the resource group | string | n/a | yes |
| location | Azure region | string | n/a | yes |
| plan_name | Name of the App Service Plan | string | n/a | yes |
| plan_sku | SKU for the App Service Plan | string | n/a | yes |
| runtime_version | Node.js runtime version | string | "20-lts" | no |
| always_on | Keep the app loaded | bool | true | no |
| app_settings | Application settings | map(string) | {} | no |
| easy_auth | Easy Auth V2 configuration | object | null | no |
| tenant_id | Azure AD tenant ID | string | null | no |
| tags | Tags to apply | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| web_app_id | The ID of the Web App |
| web_app_name | The name of the Web App |
| web_app_hostname | Default hostname of the Web App |
| web_app_url | HTTPS URL for the Web App |
| web_app_identity_principal_id | Principal ID of managed identity |
| web_app_identity_tenant_id | Tenant ID of managed identity |
| service_plan_id | The ID of the App Service Plan |
| service_plan_name | The name of the App Service Plan |
| easy_auth_login_url | Easy Auth login endpoint |

## Security Features

- HTTPS only enabled
- TLS 1.2 minimum
- FTPS disabled
- HTTP/2 enabled
- System-assigned managed identity always enabled
- Easy Auth with managed identity (no secrets)
