output "web_app_hostname" {
  description = "Default hostname for the React frontend."
  value       = azurerm_linux_web_app.react.default_hostname
}

output "web_app_url" {
  description = "HTTPS URL for the React frontend."
  value       = "https://${azurerm_linux_web_app.react.default_hostname}"
}

output "web_app_login_url" {
  description = "Easy Auth login endpoint useful for smoke tests."
  value       = "https://${azurerm_linux_web_app.react.default_hostname}/.auth/login/aad"
}

output "function_app_hostname" {
  description = "Default hostname for the FastAPI Azure Function."
  value       = azurerm_linux_function_app.api.default_hostname
}

output "function_app_api_base_url" {
  description = "Base URL (WITHOUT /api/v1 suffix) - API client adds version paths."
  value       = "https://${azurerm_linux_function_app.api.default_hostname}"
}

output "web_app_name" {
  description = "Resource name for the App Service hosting the React frontend."
  value       = azurerm_linux_web_app.react.name
}

output "web_app_plan_name" {
  description = "Service plan backing the React frontend."
  value       = azurerm_service_plan.web.name
}

output "function_app_name" {
  description = "Resource name for the FastAPI Azure Function."
  value       = azurerm_linux_function_app.api.name
}

output "function_app_plan_name" {
  description = "Service plan backing the Azure Function."
  value       = azurerm_service_plan.function.name
}

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
  description = "Name of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.this.id
}
