output "resource_groups" {
  description = "Map of created resource groups"
  value = {
    for k, rg in azurerm_resource_group.this : k => {
      id       = rg.id
      name     = rg.name
      location = rg.location
    }
  }
}

output "ids" {
  description = "Map of resource group IDs"
  value       = { for k, rg in azurerm_resource_group.this : k => rg.id }
}

output "names" {
  description = "Map of resource group names"
  value       = { for k, rg in azurerm_resource_group.this : k => rg.name }
}

output "locations" {
  description = "Map of resource group locations"
  value       = { for k, rg in azurerm_resource_group.this : k => rg.location }
}
