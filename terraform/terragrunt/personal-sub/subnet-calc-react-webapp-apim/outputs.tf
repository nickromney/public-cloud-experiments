# -----------------------------------------------------------------------------
# API Management Outputs
# -----------------------------------------------------------------------------

output "apim_name" {
  description = "Name of the API Management instance"
  value       = module.apim.name
}

output "apim_gateway_url" {
  description = "APIM Gateway URL (public endpoint)"
  value       = module.apim.gateway_url
}

output "apim_portal_url" {
  description = "APIM Developer Portal URL"
  value       = module.apim.developer_portal_url
}

output "apim_management_url" {
  description = "APIM Management API URL"
  value       = module.apim.management_api_url
}

output "apim_api_url" {
  description = "Full API URL via APIM Gateway"
  value       = "${module.apim.gateway_url}/${var.apim.api_path}"
}

output "apim_subscription_key" {
  description = "Primary subscription key for API access (if subscription required)"
  value       = var.apim.subscription_required ? azurerm_api_management_subscription.subnet_calc[0].primary_key : "N/A - subscription not required"
  sensitive   = true
}

output "apim_secondary_subscription_key" {
  description = "Secondary subscription key for API access (if subscription required)"
  value       = var.apim.subscription_required ? azurerm_api_management_subscription.subnet_calc[0].secondary_key : "N/A - subscription not required"
  sensitive   = true
}

output "apim_public_ip_addresses" {
  description = "APIM outbound public IP addresses (for NSG/firewall rules)"
  value       = module.apim.public_ip_addresses
}

# -----------------------------------------------------------------------------
# Function App Outputs
# -----------------------------------------------------------------------------

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.api.name
}

output "function_app_hostname" {
  description = "Function App default hostname (not directly accessible if NSG enforced)"
  value       = azurerm_linux_function_app.api.default_hostname
}

output "function_app_principal_id" {
  description = "Function App managed identity principal ID"
  value       = azurerm_linux_function_app.api.identity[0].principal_id
}

output "function_app_url" {
  description = "Function App URL (note: should only be accessed via APIM)"
  value       = "https://${azurerm_linux_function_app.api.default_hostname}"
}

output "function_app_access_restrictions" {
  description = "Whether IP access restrictions are enforced"
  value       = var.security.enforce_apim_only_access ? "Enabled - Only APIM IPs allowed" : "Disabled - Public access allowed"
}

# -----------------------------------------------------------------------------
# Web App Outputs
# -----------------------------------------------------------------------------

output "web_app_name" {
  description = "Name of the Web App"
  value       = azurerm_linux_web_app.react.name
}

output "web_app_hostname" {
  description = "Web App hostname"
  value       = azurerm_linux_web_app.react.default_hostname
}

output "web_app_url" {
  description = "Web App URL"
  value       = "https://${azurerm_linux_web_app.react.default_hostname}"
}

output "web_app_principal_id" {
  description = "Web App managed identity principal ID"
  value       = azurerm_linux_web_app.react.identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "application_insights_name" {
  description = "Name of Application Insights instance (existing or created)"
  value       = var.observability.use_existing ? data.azurerm_application_insights.shared[0].name : azurerm_application_insights.this[0].name
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = local.app_insights_connection
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of Log Analytics Workspace (existing or created)"
  value       = var.observability.use_existing ? data.azurerm_log_analytics_workspace.shared[0].name : azurerm_log_analytics_workspace.this[0].name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = local.log_analytics_workspace_id
}

# -----------------------------------------------------------------------------
# Security Configuration Outputs
# -----------------------------------------------------------------------------

output "security_configuration" {
  description = "Summary of security configuration"
  value = {
    apim_auth_mode           = var.apim.subscription_required ? "subscription" : "none"
    function_app_auth_mode   = "none (protected by APIM)"
    ip_restrictions_enforced = var.security.enforce_apim_only_access
    apim_rate_limit          = "${var.apim.rate_limit_per_minute} requests/minute"
  }
}

# -----------------------------------------------------------------------------
# Testing & Validation Outputs
# -----------------------------------------------------------------------------

output "test_commands" {
  description = "Commands to test the deployment"
  value = var.apim.subscription_required ? {
    health_check_via_apim = "curl -H 'Ocp-Apim-Subscription-Key: <use-primary-key>' ${module.apim.gateway_url}/${var.apim.api_path}/api/v1/health"
    get_subscription_key  = "terragrunt output -raw apim_subscription_key"
    test_web_app          = "curl https://${azurerm_linux_web_app.react.default_hostname}"
    function_app_direct   = var.security.enforce_apim_only_access ? "Direct access BLOCKED by IP restrictions" : "curl https://${azurerm_linux_function_app.api.default_hostname}/api/v1/health"
    } : {
    health_check_via_apim = "curl ${module.apim.gateway_url}/${var.apim.api_path}/api/v1/health"
    test_web_app          = "curl https://${azurerm_linux_web_app.react.default_hostname}"
    function_app_direct   = var.security.enforce_apim_only_access ? "Direct access BLOCKED by IP restrictions" : "curl https://${azurerm_linux_function_app.api.default_hostname}/api/v1/health"
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    stack_name           = "Subnet Calculator React Web App with APIM"
    apim_gateway         = module.apim.gateway_url
    api_path             = "/${var.apim.api_path}"
    web_app_url          = "https://${azurerm_linux_web_app.react.default_hostname}"
    function_app_backend = "https://${azurerm_linux_function_app.api.default_hostname}"
    auth_termination     = "APIM (${var.apim.subscription_required ? "subscription key" : "none"})"
    backend_protection   = var.security.enforce_apim_only_access ? "IP restrictions enforced" : "Public access (no restrictions)"
  }
}
