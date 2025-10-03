# Outputs for Pluralsight app module

output "resource_group_name" {
  description = "Name of the sandbox resource group"
  value       = data.azurerm_resource_group.sandbox.name
}

output "storage_accounts" {
  description = "Storage account details"
  value = {
    for k, v in azurerm_storage_account.this : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "app_service_plans" {
  description = "App Service Plan details"
  value = {
    for k, v in azurerm_service_plan.this : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "function_apps" {
  description = "Function App details"
  value = {
    for k, v in azurerm_linux_function_app.this : k => {
      id               = v.id
      name             = v.name
      default_hostname = v.default_hostname
    }
  }
}

output "static_web_apps" {
  description = "Static Web App details"
  value = {
    for k, v in azurerm_static_web_app.this : k => {
      id               = v.id
      name             = v.name
      default_hostname = v.default_host_name
      api_key          = v.api_key
    }
  }
  sensitive = true
}

output "apim_instances" {
  description = "APIM instance details"
  value = {
    for k, v in azurerm_api_management.this : k => {
      id          = v.id
      name        = v.name
      gateway_url = v.gateway_url
    }
  }
}

output "apim_apis" {
  description = "APIM API details"
  value = {
    for k, v in azurerm_api_management_api.this : k => {
      id   = v.id
      name = v.name
      path = v.path
    }
  }
}
