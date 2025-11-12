# Azure App Service Plan Module
# Map-based pattern: creates 0-to-n service plans

resource "azurerm_service_plan" "this" {
  for_each = var.service_plans

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  os_type             = each.value.os_type
  sku_name            = each.value.sku_name
  tags                = merge(var.common_tags, try(each.value.tags, {}))
}
