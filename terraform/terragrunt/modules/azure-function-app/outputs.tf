output "function_apps" {
  description = "Map of created function apps"
  value = {
    for k, app in azurerm_linux_function_app.this : k => {
      id                             = app.id
      name                           = app.name
      default_hostname               = app.default_hostname
      outbound_ip_addresses          = app.outbound_ip_addresses
      possible_outbound_ip_addresses = app.possible_outbound_ip_addresses
      identity                       = app.identity
    }
  }
}

output "ids" {
  description = "Map of function app IDs"
  value       = { for k, app in azurerm_linux_function_app.this : k => app.id }
}

output "names" {
  description = "Map of function app names"
  value       = { for k, app in azurerm_linux_function_app.this : k => app.name }
}

output "default_hostnames" {
  description = "Map of function app default hostnames"
  value       = { for k, app in azurerm_linux_function_app.this : k => app.default_hostname }
}

output "urls" {
  description = "Map of function app URLs"
  value       = { for k, app in azurerm_linux_function_app.this : k => "https://${app.default_hostname}" }
}
