output "identities" {
  description = "Map of created user-assigned identities"
  value = {
    for k, uai in azurerm_user_assigned_identity.this : k => {
      id           = uai.id
      name         = uai.name
      principal_id = uai.principal_id
      client_id    = uai.client_id
      tenant_id    = uai.tenant_id
    }
  }
}

output "ids" {
  description = "Map of identity IDs"
  value       = { for k, uai in azurerm_user_assigned_identity.this : k => uai.id }
}

output "principal_ids" {
  description = "Map of identity principal IDs (for RBAC assignments)"
  value       = { for k, uai in azurerm_user_assigned_identity.this : k => uai.principal_id }
}

output "client_ids" {
  description = "Map of identity client IDs"
  value       = { for k, uai in azurerm_user_assigned_identity.this : k => uai.client_id }
}
