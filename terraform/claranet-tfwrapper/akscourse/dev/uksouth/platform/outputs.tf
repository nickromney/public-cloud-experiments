output "resource_groups" {
  description = "All resource groups created"
  value = {
    for k, v in module.rg : k => {
      name = v.name
      id   = v.id
    }
  }
}

output "app_service_plans" {
  description = "All App Service Plans created"
  value = {
    for k, v in module.app_service_plan : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "function_apps" {
  description = "All Function Apps created"
  value = {
    for k, v in module.function_app : k => {
      id                    = v.id
      name                  = v.name
      default_hostname      = v.default_hostname
      outbound_ip_addresses = v.outbound_ip_addresses
    }
  }
}

output "log_analytics_workspaces" {
  description = "All Log Analytics Workspaces"
  sensitive   = true
  value = {
    for k, v in module.run : k => {
      id   = v.log_analytics_workspace_id
      name = v.log_analytics_workspace_name
    }
  }
}

output "storage_accounts" {
  description = "All Storage Accounts"
  value = {
    for k, v in module.storage : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "key_vaults" {
  description = "All Key Vaults"
  value = {
    for k, v in module.key_vault : k => {
      id   = v.id
      name = v.name
      uri  = v.uri
    }
  }
}
