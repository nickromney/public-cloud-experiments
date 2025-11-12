output "role_assignments" {
  description = "Map of created role assignments"
  value = {
    for k, ra in azurerm_role_assignment.this : k => {
      id                   = ra.id
      scope                = ra.scope
      role_definition_name = ra.role_definition_name
      principal_id         = ra.principal_id
    }
  }
}

output "ids" {
  description = "Map of role assignment IDs"
  value       = { for k, ra in azurerm_role_assignment.this : k => ra.id }
}
