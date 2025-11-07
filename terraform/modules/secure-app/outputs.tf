output "resource_group_name" {
  description = "Name of the resource group containing the deployment."
  value       = local.rg_name
}

output "virtual_network_id" {
  description = "ID of the created virtual network."
  value       = azurerm_virtual_network.this.id
}

output "web_app_hostname" {
  description = "Default hostname for the App Service frontend."
  value       = azurerm_linux_web_app.web.default_hostname
}

output "web_app_private_endpoint_ip" {
  description = "Private endpoint IP address for the web app (if enabled)."
  value       = var.web_app.enable_private_endpoint ? azurerm_private_endpoint.web[0].private_service_connection[0].private_ip_address : null
}

output "function_app_hostname" {
  description = "Default hostname for the Function App."
  value       = azurerm_linux_function_app.this.default_hostname
}

output "function_app_private_endpoint_ip" {
  description = "Private endpoint IP of the Function App."
  value       = var.function_app.enable_private_endpoint ? azurerm_private_endpoint.function[0].private_service_connection[0].private_ip_address : null
}

output "apim_name" {
  description = "Name of the API Management instance."
  value       = azurerm_api_management.this.name
}

output "apim_private_ip" {
  description = "Private IP address allocated to API Management."
  value       = azurerm_api_management.this.private_ip_addresses[0]
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the web app's managed identity."
  value       = azurerm_linux_web_app.web.identity[0].principal_id
}

output "apim_audience" {
  description = "The audience value for API calls (used when requesting tokens)."
  value       = local.apim_audience
}

output "apim_app_role_id" {
  description = "App role ID that calling applications must request."
  value       = one([for role in azuread_application.apim_api.app_role : role.id if role.value == "invoke"])
}
