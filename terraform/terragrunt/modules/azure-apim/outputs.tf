# -----------------------------------------------------------------------------
# APIM Instance Outputs
# -----------------------------------------------------------------------------

output "id" {
  description = "API Management instance ID"
  value       = azurerm_api_management.this.id
}

output "name" {
  description = "API Management instance name"
  value       = azurerm_api_management.this.name
}

output "gateway_url" {
  description = "API Management gateway URL"
  value       = azurerm_api_management.this.gateway_url
}

output "gateway_regional_url" {
  description = "API Management regional gateway URL"
  value       = azurerm_api_management.this.gateway_regional_url
}

output "management_api_url" {
  description = "API Management management API URL"
  value       = azurerm_api_management.this.management_api_url
}

output "portal_url" {
  description = "API Management legacy portal URL"
  value       = azurerm_api_management.this.portal_url
}

output "developer_portal_url" {
  description = "API Management developer portal URL"
  value       = azurerm_api_management.this.developer_portal_url
}

output "scm_url" {
  description = "API Management SCM URL"
  value       = azurerm_api_management.this.scm_url
}

output "public_ip_addresses" {
  description = "Public IP addresses for outbound traffic (for firewall rules)"
  value       = data.azurerm_api_management.outbound_ips.public_ip_addresses
}

output "private_ip_addresses" {
  description = "Private IP addresses (when VNet integrated)"
  value       = azurerm_api_management.this.private_ip_addresses
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = try(azurerm_api_management.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "Tenant ID of the system-assigned managed identity"
  value       = try(azurerm_api_management.this.identity[0].tenant_id, null)
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "logger_id" {
  description = "APIM logger ID (if Application Insights configured)"
  value       = try(azurerm_api_management_logger.appinsights[0].id, null)
}

output "diagnostics_id" {
  description = "APIM diagnostics ID (if Application Insights configured)"
  value       = try(azurerm_api_management_diagnostic.this[0].id, null)
}
