output "web_apps" {
  description = "Map of created web apps"
  value = {
    for k, app in azurerm_linux_web_app.this : k => {
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
  description = "Map of web app IDs"
  value       = { for k, app in azurerm_linux_web_app.this : k => app.id }
}

output "names" {
  description = "Map of web app names"
  value       = { for k, app in azurerm_linux_web_app.this : k => app.name }
}

output "default_hostnames" {
  description = "Map of web app default hostnames"
  value       = { for k, app in azurerm_linux_web_app.this : k => app.default_hostname }
}

output "urls" {
  description = "Map of web app URLs"
  value       = { for k, app in azurerm_linux_web_app.this : k => "https://${app.default_hostname}" }
}
