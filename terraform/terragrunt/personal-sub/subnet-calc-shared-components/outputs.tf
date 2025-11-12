# -----------------------------------------------------------------------------
# Resource Group Outputs (map-based)
# -----------------------------------------------------------------------------

output "resource_group_names" {
  description = "Map of created resource group names"
  value       = { for k, v in azurerm_resource_group.this : k => v.name }
}

output "resource_group_ids" {
  description = "Map of created resource group IDs"
  value       = { for k, v in azurerm_resource_group.this : k => v.id }
}

output "resource_group_locations" {
  description = "Map of created resource group locations"
  value       = { for k, v in azurerm_resource_group.this : k => v.location }
}

output "existing_resource_group_name" {
  description = "Name of existing resource group (if used)"
  value       = length(data.azurerm_resource_group.existing) > 0 ? data.azurerm_resource_group.existing[0].name : null
}

output "existing_resource_group_id" {
  description = "ID of existing resource group (if used)"
  value       = length(data.azurerm_resource_group.existing) > 0 ? data.azurerm_resource_group.existing[0].id : null
}

output "existing_resource_group_location" {
  description = "Location of existing resource group (if used)"
  value       = length(data.azurerm_resource_group.existing) > 0 ? data.azurerm_resource_group.existing[0].location : null
}

# Convenience outputs for default resource group
output "default_resource_group_name" {
  description = "Default resource group name (first created or existing)"
  value       = local.default_rg_name
}

output "default_resource_group_location" {
  description = "Default resource group location (first created or existing)"
  value       = local.default_rg_loc
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace Outputs (map-based)
# -----------------------------------------------------------------------------

output "log_analytics_workspace_names" {
  description = "Map of Log Analytics Workspace names"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.name }
}

output "log_analytics_workspace_ids" {
  description = "Map of Log Analytics Workspace IDs"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.id }
}

output "log_analytics_workspace_workspace_ids" {
  description = "Map of Log Analytics Workspace workspace IDs (GUID format)"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.workspace_id }
}

output "log_analytics_workspace_primary_shared_keys" {
  description = "Map of Log Analytics Workspace primary shared keys"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.primary_shared_key }
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Key Vault Outputs (map-based)
# -----------------------------------------------------------------------------

output "key_vault_names" {
  description = "Map of Key Vault names (with random suffix if enabled)"
  value       = { for k, v in module.key_vaults : k => v.name }
}

output "key_vault_ids" {
  description = "Map of Key Vault IDs"
  value       = { for k, v in module.key_vaults : k => v.id }
}

output "key_vault_uris" {
  description = "Map of Key Vault URIs"
  value       = { for k, v in module.key_vaults : k => v.vault_uri }
}

output "key_vault_tenant_ids" {
  description = "Map of Key Vault tenant IDs"
  value       = { for k, v in module.key_vaults : k => v.tenant_id }
}
