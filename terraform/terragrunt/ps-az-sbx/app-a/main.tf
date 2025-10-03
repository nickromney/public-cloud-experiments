# Pluralsight App Module
# All resources use for_each on maps (0 to n pattern)

# Data source for existing resource group
data "azurerm_resource_group" "sandbox" {
  name = var.existing_resource_group_name
}

# ============================================================================
# Storage Accounts - for_each pattern (0 to n)
# ============================================================================

resource "azurerm_storage_account" "this" {
  for_each = var.storage_accounts

  name                     = lower(replace("st${var.project_name}${var.environment}${each.key}", "-", ""))
  resource_group_name      = data.azurerm_resource_group.sandbox.name
  location                 = var.location
  account_tier             = each.value.account_tier
  account_replication_type = each.value.replication_type

  # Security settings
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  tags = merge(
    var.tags,
    {
      purpose = each.value.purpose
    }
  )
}

# ============================================================================
# App Service Plans - for_each pattern (0 to n)
# ============================================================================

resource "azurerm_service_plan" "this" {
  for_each = var.app_service_plans

  name                = "plan-${var.project_name}-${var.environment}-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = var.location
  os_type             = each.value.os_type
  sku_name            = each.value.sku_name

  tags = var.tags
}

# ============================================================================
# Function Apps - for_each pattern (0 to n)
# ============================================================================

resource "azurerm_linux_function_app" "this" {
  for_each = var.function_apps

  name                = "func-${var.project_name}-${var.environment}-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = var.location

  # References to other resources via keys
  service_plan_id            = azurerm_service_plan.this[each.value.app_service_plan_key].id
  storage_account_name       = azurerm_storage_account.this[each.value.storage_account_key].name
  storage_account_access_key = azurerm_storage_account.this[each.value.storage_account_key].primary_access_key

  site_config {
    application_stack {
      dotnet_version              = each.value.runtime == "dotnet-isolated" ? each.value.runtime_version : null
      use_dotnet_isolated_runtime = each.value.runtime == "dotnet-isolated" ? true : null
      python_version              = each.value.runtime == "python" ? each.value.runtime_version : null
      node_version                = each.value.runtime == "node" ? each.value.runtime_version : null
    }

    # Security
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"
  }

  app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME" = each.value.runtime == "dotnet-isolated" ? "dotnet-isolated" : each.value.runtime
    },
    each.value.app_settings
  )

  tags = var.tags
}

# ============================================================================
# Static Web Apps - for_each pattern (0 to n)
# ============================================================================

resource "azurerm_static_web_app" "this" {
  for_each = var.static_web_apps

  name                = "stapp-${var.project_name}-${var.environment}-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = var.location

  sku_tier = each.value.sku_tier
  sku_size = each.value.sku_size

  tags = var.tags
}

# ============================================================================
# API Management - for_each pattern (0 to n)
# ============================================================================

resource "azurerm_api_management" "this" {
  for_each = var.apim_instances

  name                = "apim-${var.project_name}-${var.environment}-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = var.location

  sku_name = each.value.sku_name

  publisher_name  = each.value.publisher_name
  publisher_email = each.value.publisher_email

  tags = var.tags
}

# ============================================================================
# APIM APIs - for_each pattern (0 to n)
# Links Function Apps to APIM
# ============================================================================

resource "azurerm_api_management_api" "this" {
  for_each = var.apim_apis

  name                = "api-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  api_management_name = azurerm_api_management.this[each.value.apim_key].name
  revision            = "1"
  display_name        = each.value.display_name
  path                = each.value.path
  protocols           = each.value.protocols
}

# APIM Backend - links to Function App
resource "azurerm_api_management_backend" "function_app" {
  for_each = var.apim_apis

  name                = "backend-${each.key}"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  api_management_name = azurerm_api_management.this[each.value.apim_key].name
  protocol            = "http"
  url                 = "https://${azurerm_linux_function_app.this[each.value.function_app_key].default_hostname}/api"

  resource_id = "https://management.azure.com${azurerm_linux_function_app.this[each.value.function_app_key].id}"
}
