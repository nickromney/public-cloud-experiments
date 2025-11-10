# Azure Key Vault Module
# Supports RBAC and Access Policy authorization models

# Look up current Azure context when tenant_id not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  # Generate unique suffix if requested
  use_suffix       = var.use_random_suffix ? { enabled = true } : {}
  name_with_suffix = var.use_random_suffix ? "${var.name}-${random_string.suffix["enabled"].result}" : var.name
}

resource "random_string" "suffix" {
  for_each = local.use_suffix

  length  = 4
  special = false
  upper   = false
}

resource "azurerm_key_vault" "this" {
  name                = local.name_with_suffix
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = local.tenant_id

  sku_name = var.sku_name

  # Network settings
  public_network_access_enabled   = var.public_network_access_enabled
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment

  # Soft delete and purge protection
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # Authorization model
  rbac_authorization_enabled = var.enable_rbac_authorization

  # Network ACLs
  dynamic "network_acls" {
    for_each = var.network_acls != null ? [var.network_acls] : []
    content {
      bypass                     = network_acls.value.bypass
      default_action             = network_acls.value.default_action
      ip_rules                   = try(network_acls.value.ip_rules, [])
      virtual_network_subnet_ids = try(network_acls.value.virtual_network_subnet_ids, [])
    }
  }

  tags = var.tags
}

# Access policies (only when RBAC is disabled)
resource "azurerm_key_vault_access_policy" "this" {
  for_each = var.enable_rbac_authorization ? {} : var.access_policies

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = each.value.object_id

  key_permissions         = try(each.value.key_permissions, [])
  secret_permissions      = try(each.value.secret_permissions, [])
  certificate_permissions = try(each.value.certificate_permissions, [])
  storage_permissions     = try(each.value.storage_permissions, [])
}

# Diagnostic settings (optional)
locals {
  enable_diagnostics = var.log_analytics_workspace_id != null ? { enabled = true } : {}
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.enable_diagnostics

  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = var.diagnostic_log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = var.diagnostic_metric_categories
    content {
      category = enabled_metric.value
    }
  }
}
