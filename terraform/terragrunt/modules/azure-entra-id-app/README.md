# Azure Entra ID App Registration Terraform Module

This module creates an Entra ID (Azure AD) app registration for OAuth2/OpenID Connect authentication with Azure App Service EasyAuth or MSAL.js.

## Features

- **App Registration** with web and/or SPA redirect URIs
- **Client Secret** generation and optional Key Vault storage
- **Implicit Grant Flow** configuration
- **Token Version** configuration (v1 or v2)
- **API Permissions** (Microsoft Graph User.Read by default)
- **Service Principal** creation
- **Key Vault Integration** for secure secret storage

## Usage

### Basic Web App (EasyAuth)

```hcl
module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  display_name = "Subnet Calculator - React WebApp"

  # Web redirect URIs for Azure App Service EasyAuth
  web_redirect_uris = [
    "https://web-subnet-calc-react.azurewebsites.net/.auth/login/aad/callback"
  ]

  # Enable implicit grant for EasyAuth
  implicit_grant_access_token_enabled = true
  implicit_grant_id_token_enabled     = true

  # Token v2
  requested_access_token_version = 2

  # Create client secret
  create_client_secret = true

  # Store in Key Vault
  key_vault_id = module.key_vault.id

  tags = {
    environment = "production"
    app         = "subnet-calculator"
  }
}
```

### SPA with MSAL.js

```hcl
module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  display_name = "Subnet Calculator - SPA"

  # SPA redirect URIs for MSAL.js
  spa_redirect_uris = [
    "https://web-subnet-calc-react.azurewebsites.net",
    "http://localhost:5173"  # Local development
  ]

  # Implicit grant not needed for SPA with PKCE
  implicit_grant_access_token_enabled = false
  implicit_grant_id_token_enabled     = false

  # Token v2
  requested_access_token_version = 2

  # Create client secret (optional for SPA, but useful for server-side calls)
  create_client_secret = true
  key_vault_id         = module.key_vault.id

  tags = {
    environment = "production"
  }
}
```

### With Custom API Permissions

```hcl
module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  display_name = "My App with Custom Permissions"

  web_redirect_uris = [
    "https://myapp.azurewebsites.net/.auth/login/aad/callback"
  ]

  # Default User.Read is added automatically
  add_microsoft_graph_user_read = true

  # Add custom API permissions
  required_resource_access = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
      resource_access = [
        {
          id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"  # User.Read
          type = "Scope"
        },
        {
          id   = "06da0dbc-49e2-44d2-8312-53f166ab848a"  # Directory.Read.All
          type = "Scope"
        }
      ]
    }
  ]

  tags = {
    environment = "production"
  }
}
```

### Reference in Web App EasyAuth Configuration

```hcl
module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  display_name = "Subnet Calculator EasyAuth"

  web_redirect_uris = [
    "https://${azurerm_linux_web_app.this.default_hostname}/.auth/login/aad/callback"
  ]

  create_client_secret = true
  key_vault_id         = module.key_vault.id
}

# Use in Web App EasyAuth
resource "azurerm_linux_web_app" "this" {
  name = "web-myapp"
  # ...

  auth_settings_v2 {
    auth_enabled = true

    active_directory_v2 {
      client_id                  = module.entra_id_app.application_id
      client_secret_setting_name = "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
      tenant_auth_endpoint       = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    }

    login {
      token_store_enabled = true
    }
  }

  app_settings = {
    MICROSOFT_PROVIDER_AUTHENTICATION_SECRET = module.entra_id_app.client_secret_value
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| display_name | App registration display name | `string` | n/a | yes |
| sign_in_audience | Who can sign in | `string` | `"AzureADMyOrg"` | no |
| web_redirect_uris | Web redirect URIs | `list(string)` | `[]` | no |
| spa_redirect_uris | SPA redirect URIs | `list(string)` | `[]` | no |
| implicit_grant_access_token_enabled | Enable implicit grant for access tokens | `bool` | `true` | no |
| implicit_grant_id_token_enabled | Enable implicit grant for ID tokens | `bool` | `true` | no |
| requested_access_token_version | Token version (1 or 2) | `number` | `2` | no |
| add_microsoft_graph_user_read | Add User.Read permission | `bool` | `true` | no |
| required_resource_access | Custom API permissions | `list(object)` | `[]` | no |
| create_client_secret | Create client secret | `bool` | `true` | no |
| client_secret_display_name | Client secret display name | `string` | `"terraform-generated"` | no |
| client_secret_end_date | Secret expiration (RFC3339) | `string` | `null` | no |
| key_vault_id | Key Vault ID for secret storage | `string` | `null` | no |
| client_secret_kv_name | Key Vault secret name | `string` | `""` | no |
| tags | Tags for Key Vault secret | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| application_id | Application (client) ID |
| object_id | App registration object ID |
| display_name | App display name |
| service_principal_id | Service principal object ID |
| client_secret_value | Client secret (sensitive) |
| client_secret_key_id | Client secret key ID |
| client_secret_kv_secret_id | Key Vault secret ID |
| web_redirect_uris | Web redirect URIs |
| spa_redirect_uris | SPA redirect URIs |

## Notes

- **Web vs SPA redirect URIs**: Use `web_redirect_uris` for Azure App Service EasyAuth (server-side), `spa_redirect_uris` for MSAL.js (client-side)
- **Implicit Grant**: Required for EasyAuth, not needed for SPA with PKCE
- **Token Version**: v2 tokens are recommended for new apps
- **Key Vault Storage**: When `key_vault_id` is provided, client secret is automatically stored
- **Secret Expiration**: Default is 1 year if not specified
- **Permissions**: User.Read is added by default, can be disabled with `add_microsoft_graph_user_read = false`

## EasyAuth Configuration

For Azure App Service EasyAuth:

1. Set `web_redirect_uris` to `https://<app-name>.azurewebsites.net/.auth/login/aad/callback`
2. Enable implicit grant for both access tokens and ID tokens
3. Use token version 2
4. Store client secret in Key Vault
5. Reference in app settings as `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`

## MSAL.js Configuration

For React with MSAL.js:

1. Set `spa_redirect_uris` to your app URL and localhost for development
2. Disable implicit grant (use PKCE flow)
3. Use token version 2
4. Configure MSAL in React:

```typescript
import { PublicClientApplication } from "@azure/msal-browser";

const msalConfig = {
  auth: {
    clientId: "<application_id>",
    authority: "https://login.microsoftonline.com/<tenant_id>",
    redirectUri: window.location.origin,
  },
};

const msalInstance = new PublicClientApplication(msalConfig);
```

## References

- [Azure App Service Authentication](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [MSAL.js Documentation](https://learn.microsoft.com/en-us/entra/identity-platform/msal-overview)
- [App Registration Best Practices](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration)
