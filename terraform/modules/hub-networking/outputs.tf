# Outputs for hub networking module

output "resource_group_name" {
  description = "Name of the hub resource group"
  value       = azurerm_resource_group.hub.name
}

output "resource_group_id" {
  description = "ID of the hub resource group"
  value       = azurerm_resource_group.hub.id
}

output "vnet_id" {
  description = "ID of the hub VNet"
  value       = azurerm_virtual_network.hub.id
}

output "vnet_name" {
  description = "Name of the hub VNet"
  value       = azurerm_virtual_network.hub.name
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value = {
    for k, v in azurerm_subnet.subnets : k => v.id
  }
}

output "subnet_names" {
  description = "Map of subnet names"
  value = {
    for k, v in azurerm_subnet.subnets : k => v.name
  }
}

output "firewall_subnet_id" {
  description = "ID of the Azure Firewall subnet"
  value       = azurerm_subnet.subnets["firewall"].id
}

output "gateway_subnet_id" {
  description = "ID of the Gateway subnet"
  value       = azurerm_subnet.subnets["gateway"].id
}

output "bastion_subnet_id" {
  description = "ID of the Bastion subnet"
  value       = azurerm_subnet.subnets["bastion"].id
}
