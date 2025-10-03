# Simplified outputs for Pluralsight sandbox

output "container_registries" {
  description = "Container Registries for AKS (Note: No container operations allowed in sandbox)"
  value = {
    for k, v in azurerm_container_registry.main : k => {
      name         = v.name
      login_server = v.login_server
    }
  }
}

output "aks_clusters" {
  description = "AKS Clusters"
  value = {
    for k, v in module.aks : k => {
      name               = v.name
      apiserver_endpoint = v.apiserver_endpoint
    }
  }
}

output "aks_kubeconfig_cmd" {
  description = "Commands to get AKS credentials"
  value = {
    for k, v in module.aks : k => "az aks get-credentials --resource-group ${local.resource_group_names[var.aks_clusters[k].resource_group_key]} --name ${v.name}"
  }
}

output "sandbox_info" {
  description = "Sandbox information"
  value = {
    environment   = var.environment
    expires_hours = var.sandbox_expires_in_hours
    region        = var.azure_region
  }
}
