# Azure User Assigned Identity Module
# Map-based pattern: creates 0-to-n user-assigned identities

resource "azurerm_user_assigned_identity" "this" {
  for_each = var.identities

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  tags                = merge(var.common_tags, try(each.value.tags, {}))
}
