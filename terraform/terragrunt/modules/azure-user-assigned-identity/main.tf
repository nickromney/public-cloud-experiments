# Azure User-Assigned Managed Identity Module
# Small atomic module for creating user-assigned identities
# Separates IAM concerns from application deployment

resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
