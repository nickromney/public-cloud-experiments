# -----------------------------------------------------------------------------
# Key Vault Outputs
# -----------------------------------------------------------------------------

output "id" {
  description = "Key Vault resource ID"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name (with random suffix if enabled)"
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.this.vault_uri
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_key_vault.this.resource_group_name
}

output "location" {
  description = "Azure region"
  value       = azurerm_key_vault.this.location
}

output "tenant_id" {
  description = "Tenant ID"
  value       = azurerm_key_vault.this.tenant_id
}
