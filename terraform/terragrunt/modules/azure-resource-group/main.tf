# Azure Resource Group Module
# Map-based pattern: creates 0-to-n resource groups

resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups

  name     = each.value.name
  location = each.value.location
  tags     = merge(var.common_tags, try(each.value.tags, {}))
}
