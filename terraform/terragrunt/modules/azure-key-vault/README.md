# Azure Key Vault Terraform Module

This module creates an Azure Key Vault with support for both RBAC and Access Policy authorization models.

## Features

- **RBAC Authorization** (recommended) or Access Policy model
- **Random suffix** for globally unique naming
- **Network ACLs** for private access
- **Soft delete and purge protection**
- **Diagnostic settings** integration with Log Analytics
- **Flexible permissions** via RBAC or access policies

## Usage

### Basic Usage (RBAC)

```hcl
module "key_vault" {
  source = "../../modules/azure-key-vault"

  name                = "kv-myapp"
  location            = "uksouth"
  resource_group_name = "rg-myapp"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # RBAC is enabled by default
  enable_rbac_authorization = true

  tags = {
    environment = "production"
    managed_by  = "terraform"
  }
}

# Grant RBAC permissions
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

### With Access Policies (Legacy)

```hcl
module "key_vault" {
  source = "../../modules/azure-key-vault"

  name                = "kv-myapp"
  location            = "uksouth"
  resource_group_name = "rg-myapp"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  enable_rbac_authorization = false

  access_policies = {
    "deployer" = {
      object_id = data.azurerm_client_config.current.object_id
      secret_permissions = [
        "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
      ]
    }
  }

  tags = {
    environment = "production"
  }
}
```

### With Network ACLs

```hcl
module "key_vault" {
  source = "../../modules/azure-key-vault"

  name                = "kv-myapp"
  location            = "uksouth"
  resource_group_name = "rg-myapp"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  public_network_access_enabled = false

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"]
    virtual_network_subnet_ids = [
      azurerm_subnet.private.id
    ]
  }

  tags = {
    environment = "production"
  }
}
```

### With Diagnostics

```hcl
module "key_vault" {
  source = "../../modules/azure-key-vault"

  name                = "kv-myapp"
  location            = "uksouth"
  resource_group_name = "rg-myapp"
  tenant_id           = data.azurerm_client_config.current.tenant_id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  diagnostic_log_categories = [
    "AuditEvent",
    "AzurePolicyEvaluationDetails"
  ]

  tags = {
    environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Base name of the Key Vault | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| resource_group_name | Resource group name | `string` | n/a | yes |
| tenant_id | Azure AD tenant ID | `string` | n/a | yes |
| sku_name | SKU (standard or premium) | `string` | `"standard"` | no |
| use_random_suffix | Append random suffix for uniqueness | `bool` | `true` | no |
| enable_rbac_authorization | Use RBAC instead of access policies | `bool` | `true` | no |
| access_policies | Access policies (when RBAC disabled) | `map(object)` | `{}` | no |
| public_network_access_enabled | Allow public network access | `bool` | `true` | no |
| network_acls | Network ACL configuration | `object` | `null` | no |
| soft_delete_retention_days | Retention period for soft delete (7-90) | `number` | `90` | no |
| purge_protection_enabled | Enable purge protection | `bool` | `false` | no |
| log_analytics_workspace_id | Log Analytics workspace ID | `string` | `null` | no |
| tags | Resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Key Vault resource ID |
| name | Key Vault name (with suffix) |
| vault_uri | Key Vault URI |
| resource_group_name | Resource group name |
| location | Azure region |
| tenant_id | Tenant ID |

## RBAC Roles

When using RBAC authorization, assign these built-in roles:

- **Key Vault Secrets Officer**: Full access to secrets
- **Key Vault Secrets User**: Read-only access to secrets
- **Key Vault Administrator**: Full administrative access
- **Key Vault Reader**: Read metadata only

Example:

```hcl
resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

## Notes

- Key Vault names must be globally unique (3-24 characters)
- Use `use_random_suffix = true` to append a 4-character suffix
- RBAC is the recommended authorization model for new deployments
- Soft delete is enabled by default with 90-day retention
- Purge protection prevents permanent deletion during retention period

## References

- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [RBAC Authorization](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Access Policies](https://learn.microsoft.com/en-us/azure/key-vault/general/assign-access-policy)
