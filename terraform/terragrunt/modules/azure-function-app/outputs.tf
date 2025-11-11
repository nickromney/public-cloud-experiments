output "function_app_id" {
  description = "The ID of the Function App"
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_linux_function_app.this.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.this.default_hostname
}

output "function_app_url" {
  description = "HTTPS URL for the Function App"
  value       = "https://${azurerm_linux_function_app.this.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity (null if disabled or user-assigned only)"
  value       = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? azurerm_linux_function_app.this.identity[0].principal_id : null
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the managed identity (null if disabled)"
  value       = var.managed_identity.enabled ? azurerm_linux_function_app.this.identity[0].tenant_id : null
}

output "function_app_identity" {
  description = "Full identity block of the Function App"
  value       = var.managed_identity.enabled ? azurerm_linux_function_app.this.identity[0] : null
}

output "service_plan_id" {
  description = "The ID of the App Service Plan (either existing or created)"
  value       = local.service_plan_id
}

output "service_plan_name" {
  description = "The name of the App Service Plan (either existing or created)"
  value       = local.service_plan_name
}

output "storage_account_id" {
  description = "The ID of the storage account (either existing or created)"
  value       = local.storage_account_id
}

output "storage_account_name" {
  description = "The name of the storage account (either existing or created)"
  value       = local.storage_account_name
}
