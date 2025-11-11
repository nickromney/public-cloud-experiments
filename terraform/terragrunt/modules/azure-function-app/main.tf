# Azure Function App Module
# Deploys Linux Function App with storage account and service plan

# Look up current Azure context for tenant_id when not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
}

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

  # Easy Auth V2 with Managed Identity
  # Only configured when easy_auth is provided
  dynamic "auth_settings_v2" {
    for_each = var.easy_auth != null ? [var.easy_auth] : []
    content {
      auth_enabled           = auth_settings_v2.value.enabled
      runtime_version        = auth_settings_v2.value.runtime_version
      unauthenticated_action = auth_settings_v2.value.unauthenticated_action
      default_provider       = "azureactivedirectory"

      login {
        token_store_enabled = auth_settings_v2.value.token_store_enabled
      }

      active_directory_v2 {
        client_id                            = auth_settings_v2.value.client_id
        tenant_auth_endpoint                 = auth_settings_v2.value.issuer != "" ? auth_settings_v2.value.issuer : "https://login.microsoftonline.com/${local.tenant_id}/v2.0"
        allowed_audiences                    = auth_settings_v2.value.allowed_audiences
        login_parameters                     = auth_settings_v2.value.login_parameters
        client_secret_setting_name           = auth_settings_v2.value.client_secret_setting_name != "" ? auth_settings_v2.value.client_secret_setting_name : null
        client_secret_certificate_thumbprint = null
      }
    }
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
