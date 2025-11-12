# Azure RBAC Assignments Module
# Map-based pattern: creates 0-to-n role assignments
# Reusable helper for any RBAC scenario

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id

  # Optional: use role_definition_id instead of role_definition_name
  # role_definition_id = try(each.value.role_definition_id, null)
}
