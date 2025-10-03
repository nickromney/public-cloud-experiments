module "azure_region" {
  source  = "claranet/regions/azurerm"
  version = "~> 7.0"

  azure_region = var.azure_region
}

module "rg" {
  source  = "claranet/rg/azurerm"
  version = "~> 6.0"

  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  environment    = var.environment
  stack          = var.stack
}

module "run" {
  source  = "claranet/run/azurerm"
  version = "~> 3.0"

  client_name         = var.client_name
  environment         = var.environment
  stack               = var.stack
  location            = module.azure_region.location
  location_short      = module.azure_region.location_short
  resource_group_name = module.rg.name
}

module "app_service_plan" {
  source  = "claranet/app-service-plan/azurerm"
  version = "~> 7.0"

  client_name         = var.client_name
  environment         = var.environment
  stack               = var.stack
  resource_group_name = module.rg.name
  location            = module.azure_region.location
  location_short      = module.azure_region.location_short

  logs_destinations_ids = [
    module.run.logs_storage_account_id,
    module.run.log_analytics_workspace_id,
  ]

  os_type  = "Linux"
  sku_name = "P0v3"

  extra_tags = {
    managed_by = "tfwrapper"
  }
}
