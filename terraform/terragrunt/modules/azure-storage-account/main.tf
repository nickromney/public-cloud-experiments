# Azure Storage Account Module
# Map-based pattern: creates 0-to-n storage accounts
# Optional: RBAC role assignments for each storage account

resource "azurerm_storage_account" "this" {
  for_each = var.storage_accounts

  name                     = each.value.name
  resource_group_name      = each.value.resource_group_name
  location                 = each.value.location
  account_tier             = each.value.account_tier
  account_replication_type = each.value.account_replication_type
  account_kind             = try(each.value.account_kind, "StorageV2")

  # Security settings
  min_tls_version                 = try(each.value.min_tls_version, "TLS1_2")
  allow_nested_items_to_be_public = try(each.value.allow_nested_items_to_be_public, false)
  shared_access_key_enabled       = try(each.value.shared_access_key_enabled, true)
  public_network_access_enabled   = try(each.value.public_network_access_enabled, true)

  tags = merge(var.common_tags, try(each.value.tags, {}))
}

# RBAC role assignments for storage accounts
# Flatten the map to create individual role assignments
locals {
  role_assignment_meta = flatten([
    for storage_key, storage in var.storage_accounts : [
      for assignment_key, assignment in try(storage.rbac_assignments, {}) : {
        key          = "${storage_key}-${assignment_key}-${assignment.role}"
        storage_key  = storage_key
        role         = assignment.role
        principal_id = assignment.principal_id
      }
    ]
  ])

  role_assignments = {
    for meta in local.role_assignment_meta : meta.key => {
      storage_account_id = azurerm_storage_account.this[meta.storage_key].id
      principal_id       = meta.principal_id
      role               = meta.role
    }
  }
}

resource "azurerm_role_assignment" "storage" {
  for_each = local.role_assignments

  scope                = each.value.storage_account_id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}
