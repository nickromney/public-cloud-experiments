output "storage_accounts" {
  description = "Map of created storage accounts"
  value = {
    for k, sa in azurerm_storage_account.this : k => {
      id                        = sa.id
      name                      = sa.name
      primary_blob_endpoint     = sa.primary_blob_endpoint
      primary_connection_string = sa.primary_connection_string
    }
  }
  sensitive = true # Connection strings are sensitive
}

output "ids" {
  description = "Map of storage account IDs"
  value       = { for k, sa in azurerm_storage_account.this : k => sa.id }
}

output "names" {
  description = "Map of storage account names"
  value       = { for k, sa in azurerm_storage_account.this : k => sa.name }
}

output "primary_blob_endpoints" {
  description = "Map of primary blob endpoints"
  value       = { for k, sa in azurerm_storage_account.this : k => sa.primary_blob_endpoint }
}

output "role_assignments" {
  description = "Map of RBAC role assignments created for storage accounts"
  value = {
    for k, ra in azurerm_role_assignment.storage : k => {
      id        = ra.id
      scope     = ra.scope
      role      = ra.role_definition_name
      principal = ra.principal_id
    }
  }
}
