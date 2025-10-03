output "resource_groups" {
  description = "All resource groups created"
  value = {
    for k, v in module.rg : k => {
      name = v.name
      id   = v.id
    }
  }
}

output "container_registries" {
  description = "All Container Registries created for AKS testing"
  value = {
    for k, v in module.container_registry : k => {
      id             = v.id
      name           = v.name
      login_server   = v.login_server
      admin_username = v.admin_username
      sku            = v.sku
    }
  }
  sensitive = true
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

output "vnets" {
  description = "All Virtual Networks"
  value = {
    for k, v in module.vnet : k => {
      id   = v.id
      name = v.name
      # Note: cidrs is not exposed by Claranet VNet module outputs
    }
  }
}

output "subnets" {
  description = "All Subnets"
  value = {
    for k, v in module.subnet : k => {
      id   = v.id
      name = v.name
      # Note: cidrs is not exposed by Claranet Subnet module outputs
    }
  }
}

output "aks_clusters" {
  description = "All AKS Clusters"
  value = {
    for k, v in module.aks : k => {
      id                     = v.id
      name                   = v.name
      kube_config_raw        = v.kube_config_raw
      host                   = v.host
      client_certificate     = v.client_certificate
      client_key             = v.client_key
      cluster_ca_certificate = v.cluster_ca_certificate
      node_resource_group    = v.node_resource_group
      oidc_issuer_url        = v.oidc_issuer_url
    }
  }
  sensitive = true
}

output "aks_ssh_private_keys" {
  description = "SSH private keys for AKS nodes"
  value = {
    for k, v in tls_private_key.aks_ssh : k => v.private_key_pem
  }
  sensitive = true
}

output "sandbox_info" {
  description = "Sandbox information"
  value = {
    environment   = var.environment
    expires_hours = var.sandbox_expires_in_hours
    region        = var.azure_region
    client_name   = var.client_name
  }
}
