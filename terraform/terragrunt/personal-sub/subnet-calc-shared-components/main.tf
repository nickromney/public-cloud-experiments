locals {
  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
  }, var.tags)
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

locals {
  # Resource group maps: create new or reference existing
  resource_groups_to_create = var.create_resource_group ? {
    main = {
      name     = var.resource_group_name
      location = var.location
    }
  } : {}

  resource_groups_existing = var.create_resource_group ? {} : {
    main = {}
  }

  # Merge created and existing resource groups
  resource_group_names = merge(
    { for k, v in azurerm_resource_group.this : k => v.name },
    { for k, v in data.azurerm_resource_group.this : k => v.name }
  )

  resource_group_locations = merge(
    { for k, v in azurerm_resource_group.this : k => v.location },
    { for k, v in data.azurerm_resource_group.this : k => v.location }
  )

  # Final values
  rg_name = local.resource_group_names["main"]
  rg_loc  = local.resource_group_locations["main"]
}

resource "azurerm_resource_group" "this" {
  for_each = local.resource_groups_to_create

  name     = each.value.name
  location = each.value.location
  tags     = local.common_tags

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "Resource group creation failed - no ID returned"
    }
  }
}

data "azurerm_resource_group" "this" {
  for_each = local.resource_groups_existing

  name = var.resource_group_name

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "Resource group '${var.resource_group_name}' does not exist"
    }
  }
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.project_name}-${var.component_name}-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags

  lifecycle {
    precondition {
      condition     = local.rg_name != ""
      error_message = "Resource group name must be set before creating Log Analytics workspace"
    }

    postcondition {
      condition     = self.id != "" && self.workspace_id != ""
      error_message = "Log Analytics workspace creation failed"
    }
  }
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

locals {
  # Key Vault names have a 24 character limit (before random suffix)
  # Use abbreviated project name: sc = subnet-calc
  kv_name = "kv-sc-${var.component_name}-${var.environment}"
}

module "key_vault" {
  source = "../../modules/azure-key-vault"

  name                = local.kv_name
  location            = local.rg_loc
  resource_group_name = local.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name          = var.key_vault_sku
  use_random_suffix = var.key_vault_use_random_suffix

  # Enable RBAC authorization model
  enable_rbac_authorization = true

  # Security settings
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  # Don't pass workspace ID to module - will create diagnostics separately below
  log_analytics_workspace_id = null

  tags = local.common_tags
}

# Key Vault diagnostics - created separately to avoid circular dependency
resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "keyvault-diagnostics"
  target_resource_id         = module.key_vault.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset([
      "AuditEvent",
      "AzurePolicyEvaluationDetails"
    ])
    content {
      category = enabled_log.value
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azurerm_log_analytics_workspace.this,
    module.key_vault
  ]
}

# Grant current user Key Vault Secrets Officer role
resource "azurerm_role_assignment" "kv_secrets_officer_current_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
