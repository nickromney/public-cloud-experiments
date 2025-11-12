output "service_plans" {
  description = "Map of created service plans"
  value = {
    for k, sp in azurerm_service_plan.this : k => {
      id       = sp.id
      name     = sp.name
      location = sp.location
      sku_name = sp.sku_name
    }
  }
}

output "ids" {
  description = "Map of service plan IDs"
  value       = { for k, sp in azurerm_service_plan.this : k => sp.id }
}

output "names" {
  description = "Map of service plan names"
  value       = { for k, sp in azurerm_service_plan.this : k => sp.name }
}
