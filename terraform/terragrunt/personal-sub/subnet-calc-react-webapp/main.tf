# React Web App + Function App Stack
# Uses modular architecture for reusability

# Look up current Azure context when tenant_id not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
  }, var.tags)

  web_app_name      = var.web_app.name != "" ? var.web_app.name : "web-${var.project_name}-${var.environment}-react"
  function_app_name = var.function_app.name != "" ? var.function_app.name : "func-${var.project_name}-${var.environment}-api"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

locals {
  # Resource group maps: create new or reference existing
  resource_groups_to_create = var.create_resource_group ? {
    main = {
      name     = var.resource_group_name
      location = var.location
    }
  } : {}

  resource_groups_existing = var.create_resource_group ? {} : {
    main = {}
  }

  # Merge created and existing resource groups
  resource_group_names = merge(
    { for k, v in azurerm_resource_group.this : k => v.name },
    { for k, v in data.azurerm_resource_group.this : k => v.name }
  )

  resource_group_locations = merge(
    { for k, v in azurerm_resource_group.this : k => v.location },
    { for k, v in data.azurerm_resource_group.this : k => v.location }
  )

  # Final values
  rg_name = local.resource_group_names["main"]
  rg_loc  = local.resource_group_locations["main"]
}

resource "azurerm_resource_group" "this" {
  for_each = local.resource_groups_to_create

  name     = each.value.name
  location = each.value.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "this" {
  for_each = local.resource_groups_existing

  name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# Application Insights & Log Analytics
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.project_name}-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.project_name}-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  retention_in_days   = var.observability.app_insights_retention_days
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Function App Module (FastAPI backend)
# -----------------------------------------------------------------------------

module "function_app" {
  source = "../../modules/azure-function-app"

  name                = local.function_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  plan_name = "plan-${var.project_name}-${var.environment}-func"
  plan_sku  = var.function_app.plan_sku

  runtime         = var.function_app.runtime
  runtime_version = var.function_app.runtime_version

  storage_account_name          = var.function_app.storage_account_name
  public_network_access_enabled = var.function_app.public_network_access_enabled
  cors_allowed_origins          = var.function_app.cors_allowed_origins

  app_settings = merge({
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
  }, var.function_app.app_settings)

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Web App Module (React SPA with optional Easy Auth)
# -----------------------------------------------------------------------------

module "web_app" {
  source = "../../modules/azure-web-app"

  name                = local.web_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  plan_name = "plan-${var.project_name}-${var.environment}-web"
  plan_sku  = var.web_app.plan_sku

  runtime_version = var.web_app.runtime_version
  startup_command = var.web_app.startup_command
  always_on       = var.web_app.always_on

  tenant_id = local.tenant_id
  easy_auth = var.web_app.easy_auth

  app_settings = merge({
    "WEBSITE_RUN_FROM_PACKAGE"              = "0"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~${var.web_app.runtime_version}"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"
    "API_BASE_URL"                          = var.web_app.api_base_url != "" ? var.web_app.api_base_url : module.function_app.function_app_url
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
  }, var.web_app.app_settings)

  tags = local.common_tags
}
