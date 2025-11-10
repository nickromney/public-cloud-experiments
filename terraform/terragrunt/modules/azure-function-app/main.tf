# Azure Function App Module
# Deploys Linux Function App with storage account and service plan

# App Service Plan for Function App
resource "azurerm_service_plan" "this" {
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "this" {
  name                       = var.storage_account_name != "" ? var.storage_account_name : lower(replace("st${var.name}", "-", ""))
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true
  tags                       = var.tags
}

# Linux Function App
resource "azurerm_linux_function_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key

  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled

  site_config {
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"

    cors {
      support_credentials = var.cors_support_credentials
      allowed_origins     = var.cors_allowed_origins
    }

    application_stack {
      python_version = var.runtime == "python" ? var.runtime_version : null
      node_version   = var.runtime == "node" ? var.runtime_version : null
      dotnet_version = var.runtime == "dotnet-isolated" ? var.runtime_version : null
    }
  }

  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"       = var.runtime == "dotnet-isolated" ? "dotnet-isolated" : var.runtime
    "FUNCTIONS_EXTENSION_VERSION"    = "~4"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    # Azure auto-builds dependencies from requirements.txt during zip deployment (approach #1)
    # Don't set WEBSITE_RUN_FROM_PACKAGE - let Azure extract and build
  }, var.app_settings)

  identity {
    type = "SystemAssigned"
  }

  # Ignore Azure-managed Application Insights settings in site_config
  # Azure automatically syncs these from app_settings, causing drift
  lifecycle {
    ignore_changes = [
      site_config[0].application_insights_connection_string,
      site_config[0].application_insights_key
    ]
  }

  tags = var.tags
}
