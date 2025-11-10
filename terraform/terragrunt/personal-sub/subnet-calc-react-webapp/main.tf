locals {
  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
  }, var.tags)

  web_app_name          = var.web_app.name != "" ? var.web_app.name : "web-${var.project_name}-${var.environment}-react"
  function_app_name     = var.function_app.name != "" ? var.function_app.name : "func-${var.project_name}-${var.environment}-api"
  easy_auth_secret_name = var.web_app.easy_auth != null ? var.web_app.easy_auth.client_secret_setting_name : null
  computed_api_base_url = var.web_app.api_base_url != "" ? var.web_app.api_base_url : "https://${azurerm_linux_function_app.api.default_hostname}"
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
# Function App (FastAPI backend)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "function" {
  name                = "plan-${var.project_name}-${var.environment}-func"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.function_app.plan_sku
  tags                = local.common_tags
}

resource "azurerm_storage_account" "function" {
  name                     = var.function_app.storage_account_name != "" ? var.function_app.storage_account_name : lower(replace("st${var.project_name}${var.environment}func", "-", ""))
  resource_group_name      = local.rg_name
  location                 = local.rg_loc
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}

resource "azurerm_linux_function_app" "api" {
  name                = local.function_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc
  service_plan_id     = azurerm_service_plan.function.id

  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key

  https_only                    = true
  public_network_access_enabled = var.function_app.public_network_access_enabled

  site_config {
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"

    cors {
      support_credentials = false
      allowed_origins     = var.function_app.cors_allowed_origins
    }

    application_stack {
      python_version = var.function_app.runtime == "python" ? var.function_app.runtime_version : null
      node_version   = var.function_app.runtime == "node" ? var.function_app.runtime_version : null
      dotnet_version = var.function_app.runtime == "dotnet-isolated" ? var.function_app.runtime_version : null
    }
  }

  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"              = var.function_app.runtime == "dotnet-isolated" ? "dotnet-isolated" : var.function_app.runtime
    "FUNCTIONS_EXTENSION_VERSION"           = "~4"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
  }, var.function_app.app_settings)

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Web App (React SPA + Easy Auth)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "web" {
  name                = "plan-${var.project_name}-${var.environment}-web"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.web_app.plan_sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "react" {
  name                = local.web_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc
  service_plan_id     = azurerm_service_plan.web.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    always_on              = var.web_app.always_on
    vnet_route_all_enabled = false
    default_documents      = ["index.html"]

    application_stack {
      node_version = var.web_app.runtime_version
    }
  }

  app_settings = merge({
    "WEBSITE_RUN_FROM_PACKAGE"              = "0"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~${var.web_app.runtime_version}"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "false"
    "API_BASE_URL"                          = local.computed_api_base_url
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    },
    (var.web_app.easy_auth != null && var.web_app.easy_auth.client_secret != "" ? {
      (local.easy_auth_secret_name) = var.web_app.easy_auth.client_secret
    } : {}),
  var.web_app.app_settings)

  dynamic "auth_settings_v2" {
    for_each = var.web_app.easy_auth != null ? [var.web_app.easy_auth] : []
    content {
      auth_enabled           = auth_settings_v2.value.enabled
      runtime_version        = auth_settings_v2.value.runtime_version
      unauthenticated_action = auth_settings_v2.value.unauthenticated_action
      default_provider       = "azureactivedirectory"

      login {
        token_store_enabled = auth_settings_v2.value.token_store_enabled
      }

      active_directory_v2 {
        client_id                  = auth_settings_v2.value.client_id
        client_secret_setting_name = auth_settings_v2.value.client_secret_setting_name
        tenant_auth_endpoint       = auth_settings_v2.value.issuer != "" ? auth_settings_v2.value.issuer : "https://login.microsoftonline.com/${coalesce(auth_settings_v2.value.tenant_id, var.tenant_id)}/v2.0"
        allowed_audiences          = auth_settings_v2.value.allowed_audiences
        login_parameters           = auth_settings_v2.value.login_parameters
      }
    }
  }

  tags = local.common_tags
}
