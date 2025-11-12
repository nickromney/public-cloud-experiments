data "azurerm_client_config" "current" {}

locals {
  common_tags = merge({
    environment = var.environment
    managed_by  = "terragrunt"
  }, var.tags)
}

# -----------------------------------------------------------------------------
# Resource Groups (0-to-n pattern)
# -----------------------------------------------------------------------------

# Create new resource groups (if map is populated)
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups

  name     = each.value.name
  location = each.value.location
  tags     = merge(local.common_tags, each.value.tags)

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "Resource group '${each.value.name}' creation failed - no ID returned"
    }
  }
}

# Reference existing resource group (if map is empty and existing_resource_group_name is set)
data "azurerm_resource_group" "existing" {
  count = length(var.resource_groups) == 0 && var.existing_resource_group_name != "" ? 1 : 0

  name = var.existing_resource_group_name

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "Resource group '${var.existing_resource_group_name}' does not exist"
    }
  }
}

# Resolve resource group name and location
locals {
  # Merge created and existing resource groups
  resource_group_names = merge(
    { for k, v in azurerm_resource_group.this : k => v.name },
    length(data.azurerm_resource_group.existing) > 0 ? { main = data.azurerm_resource_group.existing[0].name } : {}
  )

  resource_group_locations = merge(
    { for k, v in azurerm_resource_group.this : k => v.location },
    length(data.azurerm_resource_group.existing) > 0 ? { main = data.azurerm_resource_group.existing[0].location } : {}
  )

  # Default resource group for shared resources (use first created or existing)
  default_rg_name = length(local.resource_group_names) > 0 ? values(local.resource_group_names)[0] : ""
  default_rg_loc  = length(local.resource_group_locations) > 0 ? values(local.resource_group_locations)[0] : ""
}

# -----------------------------------------------------------------------------
# Log Analytics Workspaces (0-to-n pattern)
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  for_each = var.log_analytics_workspaces

  name                = each.value.name
  location            = local.default_rg_loc
  resource_group_name = local.default_rg_name
  sku                 = each.value.sku
  retention_in_days   = each.value.retention_in_days
  tags                = merge(local.common_tags, each.value.tags)

  lifecycle {
    precondition {
      condition     = local.default_rg_name != ""
      error_message = "Resource group must be created or specified before creating Log Analytics workspace"
    }

    postcondition {
      condition     = self.id != "" && self.workspace_id != ""
      error_message = "Log Analytics workspace '${each.value.name}' creation failed"
    }
  }

  depends_on = [azurerm_resource_group.this, data.azurerm_resource_group.existing]
}

# -----------------------------------------------------------------------------
# Key Vaults (0-to-n pattern)
# -----------------------------------------------------------------------------

module "key_vaults" {
  source = "../../modules/azure-key-vault"

  for_each = var.key_vaults

  name                = each.value.name
  location            = local.default_rg_loc
  resource_group_name = local.default_rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name          = each.value.sku
  use_random_suffix = each.value.use_random_suffix

  # Enable RBAC authorization model
  enable_rbac_authorization = each.value.enable_rbac_authorization

  # Security settings
  purge_protection_enabled   = each.value.purge_protection_enabled
  soft_delete_retention_days = each.value.soft_delete_retention_days

  # Don't pass workspace ID to module - will create diagnostics separately below
  log_analytics_workspace_id = null

  tags = merge(local.common_tags, each.value.tags)

  depends_on = [azurerm_resource_group.this, data.azurerm_resource_group.existing]
}

# Key Vault diagnostics - only if Log Analytics workspace and diagnostic config provided
resource "azurerm_monitor_diagnostic_setting" "kv" {
  for_each = {
    for k, v in var.key_vaults : k => v
    if v.log_analytics_workspace_key != null && contains(keys(azurerm_log_analytics_workspace.this), v.log_analytics_workspace_key)
  }

  name                       = "keyvault-diagnostics"
  target_resource_id         = module.key_vaults[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[each.value.log_analytics_workspace_key].id

  dynamic "enabled_log" {
    for_each = toset([
      "AuditEvent",
      "AzurePolicyEvaluationDetails"
    ])
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [
    azurerm_log_analytics_workspace.this,
    module.key_vaults
  ]
}

# Grant current user Key Vault Secrets Officer role (if enabled)
resource "azurerm_role_assignment" "kv_secrets_officer_current_user" {
  for_each = var.grant_current_user_key_vault_access ? var.key_vaults : {}

  scope                = module.key_vaults[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [module.key_vaults]
}
