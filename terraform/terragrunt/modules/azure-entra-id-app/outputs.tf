# -----------------------------------------------------------------------------
# App Registration Outputs
# -----------------------------------------------------------------------------

output "application_id" {
  description = "Application (client) ID"
  value       = azuread_application.this.client_id
}

output "object_id" {
  description = "Object ID of the app registration"
  value       = azuread_application.this.object_id
}

output "display_name" {
  description = "Display name of the app"
  value       = azuread_application.this.display_name
}

output "service_principal_id" {
  description = "Service principal object ID"
  value       = azuread_service_principal.this.object_id
}

output "service_principal_application_id" {
  description = "Service principal application ID"
  value       = azuread_service_principal.this.client_id
}

output "client_secret_value" {
  description = "Client secret value (sensitive, only if created)"
  value       = var.create_client_secret ? azuread_application_password.this["enabled"].value : null
  sensitive   = true
}

output "client_secret_key_id" {
  description = "Client secret key ID"
  value       = var.create_client_secret ? azuread_application_password.this["enabled"].key_id : null
}

output "client_secret_kv_secret_id" {
  description = "Key Vault secret ID for client secret (if stored in Key Vault)"
  value       = var.create_client_secret && var.key_vault_id != null ? azurerm_key_vault_secret.client_secret["enabled"].id : null
}

output "web_redirect_uris" {
  description = "Web redirect URIs"
  value       = var.web_redirect_uris
}

output "spa_redirect_uris" {
  description = "SPA redirect URIs"
  value       = var.spa_redirect_uris
}

output "identifier_uris" {
  description = "Application ID URIs (audience)"
  value       = azuread_application.this.identifier_uris
}

output "oauth2_permission_scope_ids" {
  description = "Map of scope value to scope ID"
  value       = { for scope in var.oauth2_permission_scopes : scope.value => scope.id }
}

output "app_role_ids" {
  description = "Map of role value to role ID"
  value       = { for role in var.app_roles : role.value => role.id }
}
