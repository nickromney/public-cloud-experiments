# Entra ID App Registration Outputs
output "entra_id_app_client_id" {
  description = "Application (client) ID of the Entra ID app registration."
  value       = module.entra_id_app.application_id
}

output "entra_id_app_object_id" {
  description = "Object ID of the Entra ID app registration."
  value       = module.entra_id_app.object_id
}

output "entra_id_app_display_name" {
  description = "Display name of the Entra ID app registration."
  value       = module.entra_id_app.display_name
}

output "entra_id_app_service_principal_id" {
  description = "Service principal object ID for the Entra ID app."
  value       = module.entra_id_app.service_principal_id
}

# Web App Outputs
output "web_app_hostname" {
  description = "Default hostname for the React frontend."
  value       = module.web_app.web_app_hostname
}

output "web_app_url" {
  description = "HTTPS URL for the React frontend."
  value       = module.web_app.web_app_url
}

output "web_app_login_url" {
  description = "Easy Auth login endpoint useful for smoke tests."
  value       = module.web_app.easy_auth_login_url
}

output "web_app_name" {
  description = "Resource name for the App Service hosting the React frontend."
  value       = module.web_app.web_app_name
}

output "web_app_plan_name" {
  description = "Service plan backing the React frontend."
  value       = module.web_app.service_plan_name
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the web app's managed identity."
  value       = module.web_app.web_app_identity_principal_id
}

# Function App Outputs
output "function_app_hostname" {
  description = "Default hostname for the FastAPI Azure Function."
  value       = module.function_app.function_app_hostname
}

output "function_app_api_base_url" {
  description = "Base URL (WITHOUT /api/v1 suffix) - API client adds version paths."
  value       = module.function_app.function_app_url
}

output "function_app_name" {
  description = "Resource name for the FastAPI Azure Function."
  value       = module.function_app.function_app_name
}

output "function_app_plan_name" {
  description = "Service plan backing the Azure Function."
  value       = module.function_app.service_plan_name
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the function app's managed identity."
  value       = module.function_app.function_app_identity_principal_id
}

# Observability Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance."
  value       = azurerm_application_insights.this.name
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the shared Log Analytics Workspace (from subnet-calc-shared-components)."
  value       = data.azurerm_log_analytics_workspace.shared.name
}

output "log_analytics_workspace_id" {
  description = "ID of the shared Log Analytics Workspace (from subnet-calc-shared-components)."
  value       = data.azurerm_log_analytics_workspace.shared.id
}

# Resource Group Output
output "resource_group_name" {
  description = "Name of the resource group."
  value       = local.rg_name
}
