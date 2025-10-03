terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${var.client_name}-${var.environment}-${var.stack}-rg"
  location = var.location

  tags = {
    environment = var.environment
    stack       = var.stack
    client      = var.client_name
    managed_by  = "terragrunt"
  }
}

resource "azurerm_service_plan" "main" {
  name                = "${var.client_name}-${var.environment}-${var.stack}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  os_type  = "Linux"
  sku_name = "B2"

  tags = {
    environment = var.environment
    stack       = var.stack
    client      = var.client_name
    managed_by  = "terragrunt"
  }
}
