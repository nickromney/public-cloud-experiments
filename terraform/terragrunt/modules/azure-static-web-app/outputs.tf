output "static_web_app_ids" {
  description = "Map of Static Web App resource IDs"
  value = {
    for key, swa in azurerm_static_web_app.this : key => swa.id
  }
}

output "static_web_app_default_hostnames" {
  description = "Map of Static Web App default hostnames"
  value = {
    for key, swa in azurerm_static_web_app.this : key => swa.default_host_name
  }
}

output "static_web_app_api_keys" {
  description = "Map of Static Web App API keys (sensitive)"
  sensitive   = true
  value = {
    for key, swa in azurerm_static_web_app.this : key => swa.api_key
  }
}

output "function_app_ids" {
  description = "Map of Function App resource IDs"
  value = {
    for key, func in azurerm_linux_function_app.this : key => func.id
  }
}

output "function_app_default_hostnames" {
  description = "Map of Function App default hostnames"
  value = {
    for key, func in azurerm_linux_function_app.this : key => func.default_hostname
  }
}

output "app_service_plan_ids" {
  description = "Map of App Service Plan resource IDs"
  value = {
    for key, plan in azurerm_service_plan.this : key => plan.id
  }
}

output "storage_account_ids" {
  description = "Map of Storage Account resource IDs"
  value = {
    for key, sa in azurerm_storage_account.this : key => sa.id
  }
}

output "storage_account_primary_access_keys" {
  description = "Map of Storage Account primary access keys (sensitive)"
  sensitive   = true
  value = {
    for key, sa in azurerm_storage_account.this : key => sa.primary_access_key
  }
}
