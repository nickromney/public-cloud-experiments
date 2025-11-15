# -----------------------------------------------------------------------------
# Entra ID App Registration Outputs (map-based)
# -----------------------------------------------------------------------------

output "entra_id_app_client_ids" {
  description = "Map of application (client) IDs for Entra ID app registrations"
  value       = { for k, v in module.entra_id_app : k => v.application_id }
}

output "entra_id_app_object_ids" {
  description = "Map of object IDs for Entra ID app registrations"
  value       = { for k, v in module.entra_id_app : k => v.object_id }
}

output "entra_id_app_service_principal_ids" {
  description = "Map of service principal object IDs for Entra ID apps"
  value       = { for k, v in module.entra_id_app : k => v.service_principal_id }
}

# -----------------------------------------------------------------------------
# Web App Outputs (map-based)
# -----------------------------------------------------------------------------

output "web_app_names" {
  description = "Map of web app resource names"
  value       = module.web_apps.names
}

output "web_app_default_hostnames" {
  description = "Map of default hostnames for web apps"
  value       = module.web_apps.default_hostnames
}

output "web_app_urls" {
  description = "Map of HTTPS URLs for web apps"
  value       = module.web_apps.urls
}

output "web_app_ids" {
  description = "Map of web app resource IDs"
  value       = module.web_apps.ids
}

# -----------------------------------------------------------------------------
# Function App Outputs (map-based)
# -----------------------------------------------------------------------------

output "function_app_names" {
  description = "Map of function app resource names"
  value       = module.function_apps.names
}

output "function_app_default_hostnames" {
  description = "Map of default hostnames for function apps"
  value       = module.function_apps.default_hostnames
}

output "function_app_urls" {
  description = "Map of HTTPS URLs for function apps"
  value       = module.function_apps.urls
}

output "function_app_ids" {
  description = "Map of function app resource IDs"
  value       = module.function_apps.ids
}

# -----------------------------------------------------------------------------
# Observability Outputs (map-based)
# -----------------------------------------------------------------------------

output "log_analytics_workspace_names" {
  description = "Map of Log Analytics Workspace names"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.name }
}

output "log_analytics_workspace_ids" {
  description = "Map of Log Analytics Workspace IDs"
  value       = { for k, v in azurerm_log_analytics_workspace.this : k => v.id }
}

output "application_insights_names" {
  description = "Map of Application Insights instance names"
  value       = { for k, v in azurerm_application_insights.this : k => v.name }
}

output "application_insights_connection_strings" {
  description = "Map of Application Insights connection strings"
  value       = { for k, v in azurerm_application_insights.this : k => v.connection_string }
  sensitive   = true
}

output "application_insights_instrumentation_keys" {
  description = "Map of Application Insights instrumentation keys"
  value       = { for k, v in azurerm_application_insights.this : k => v.instrumentation_key }
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Resource Group Output
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = data.azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = data.azurerm_resource_group.main.location
}

# -----------------------------------------------------------------------------
# Convenience outputs for deployment scripts (singular values)
# -----------------------------------------------------------------------------

output "function_app_name" {
  description = "Name of the API function app (convenience output for deployment)"
  value       = try(module.function_apps.names["api"], null)
}

output "web_app_name" {
  description = "Name of the frontend web app (convenience output for deployment)"
  value       = try(module.web_apps.names["frontend"], null)
}

output "function_app_api_base_url" {
  description = "Base URL for the API function app (convenience output for deployment)"
  value       = try(module.function_apps.urls["api"], null)
}
