output "web_app_id" {
  description = "The ID of the Web App"
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "The name of the Web App"
  value       = azurerm_linux_web_app.this.name
}

output "web_app_hostname" {
  description = "Default hostname of the Web App"
  value       = azurerm_linux_web_app.this.default_hostname
}

output "web_app_url" {
  description = "HTTPS URL for the Web App"
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity (null if disabled or user-assigned only)"
  value       = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? azurerm_linux_web_app.this.identity[0].principal_id : null
}

output "web_app_identity_tenant_id" {
  description = "Tenant ID of the managed identity (null if disabled)"
  value       = var.managed_identity.enabled ? azurerm_linux_web_app.this.identity[0].tenant_id : null
}

output "web_app_identity" {
  description = "Full identity block of the Web App"
  value       = var.managed_identity.enabled ? azurerm_linux_web_app.this.identity[0] : null
}

output "service_plan_id" {
  description = "The ID of the App Service Plan (created or existing)"
  value       = local.service_plan_id
}

output "service_plan_name" {
  description = "The name of the App Service Plan (created or existing)"
  value       = local.existing_service_plan_id != null ? data.azurerm_service_plan.existing[0].name : azurerm_service_plan.this[0].name
}

output "user_assigned_identity_id" {
  description = "The ID of the created user-assigned managed identity (null if not created)"
  value       = local.create_uai ? azurerm_user_assigned_identity.this[0].id : null
}

output "user_assigned_identity_client_id" {
  description = "The client ID of the created user-assigned managed identity (null if not created)"
  value       = local.uai_client_id
}

output "user_assigned_identity_principal_id" {
  description = "The principal ID of the created user-assigned managed identity (null if not created)"
  value       = local.uai_principal_id
}

output "easy_auth_login_url" {
  description = "Easy Auth login endpoint (Azure AD)"
  value       = "https://${azurerm_linux_web_app.this.default_hostname}/.auth/login/aad"
}
