output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.rg.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = module.rg.id
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = module.app_service_plan.id
}

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = module.app_service_plan.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = module.run.log_analytics_workspace_id
}

output "logs_storage_account_id" {
  description = "ID of the Logs Storage Account"
  value       = module.run.logs_storage_account_id
}
