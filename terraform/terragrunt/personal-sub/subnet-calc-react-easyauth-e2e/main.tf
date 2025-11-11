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

locals {
  # Observability maps: use existing or create new
  observability_existing = var.observability.use_existing ? { enabled = true } : {}
  observability_create   = var.observability.use_existing ? {} : { enabled = true }
}

data "azurerm_log_analytics_workspace" "shared" {
  for_each = local.observability_existing

  name                = var.observability.existing_log_analytics_name
  resource_group_name = var.observability.existing_resource_group_name
}

data "azurerm_application_insights" "shared" {
  for_each = local.observability_existing

  name                = var.observability.existing_app_insights_name
  resource_group_name = var.observability.existing_resource_group_name
}

# Create new resources if not using existing
resource "azurerm_log_analytics_workspace" "this" {
  for_each = local.observability_create

  name                = "log-${var.project_name}-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.observability.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  for_each = local.observability_create

  name                = "appi-${var.project_name}-easyauth-e2e-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  workspace_id        = azurerm_log_analytics_workspace.this["enabled"].id
  application_type    = "web"
  retention_in_days   = var.observability.app_insights_retention_days
  tags                = local.common_tags
}

locals {
  # Merge existing and created observability resources
  log_analytics_ids = merge(
    { for k, v in data.azurerm_log_analytics_workspace.shared : k => v.id },
    { for k, v in azurerm_log_analytics_workspace.this : k => v.id }
  )
  log_analytics_names = merge(
    { for k, v in data.azurerm_log_analytics_workspace.shared : k => v.name },
    { for k, v in azurerm_log_analytics_workspace.this : k => v.name }
  )
  app_insights_keys = merge(
    { for k, v in data.azurerm_application_insights.shared : k => v.instrumentation_key },
    { for k, v in azurerm_application_insights.this : k => v.instrumentation_key }
  )
  app_insights_connections = merge(
    { for k, v in data.azurerm_application_insights.shared : k => v.connection_string },
    { for k, v in azurerm_application_insights.this : k => v.connection_string }
  )
  app_insights_names = merge(
    { for k, v in data.azurerm_application_insights.shared : k => v.name },
    { for k, v in azurerm_application_insights.this : k => v.name }
  )

  log_analytics_workspace_id   = local.log_analytics_ids["enabled"]
  log_analytics_workspace_name = local.log_analytics_names["enabled"]
  app_insights_key             = local.app_insights_keys["enabled"]
  app_insights_connection      = local.app_insights_connections["enabled"]
  app_insights_name            = local.app_insights_names["enabled"]
}

# -----------------------------------------------------------------------------
# Entra ID App Registration (for Easy Auth with Managed Identity)
# -----------------------------------------------------------------------------

module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  display_name     = var.entra_id_app.display_name
  sign_in_audience = var.entra_id_app.sign_in_audience

  # Web redirect URIs for Easy Auth callback
  web_redirect_uris = [
    "https://${local.web_app_name}.azurewebsites.net/.auth/login/aad/callback"
  ]

  # Identifier URIs (audience) for token validation
  identifier_uris = var.entra_id_app.identifier_uris

  # No client secret needed - using managed identity
  create_client_secret = false

  # Microsoft Graph User.Read permission
  add_microsoft_graph_user_read = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Function App Module (FastAPI backend)
# -----------------------------------------------------------------------------

module "function_app" {
  source = "../../modules/azure-function-app"

  name                = local.function_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  plan_name = "plan-${var.project_name}-${var.environment}-func-easyauth-e2e"
  plan_sku  = var.function_app.plan_sku

  runtime         = var.function_app.runtime
  runtime_version = var.function_app.runtime_version

  storage_account_name          = var.function_app.storage_account_name
  public_network_access_enabled = var.function_app.public_network_access_enabled
  cors_allowed_origins          = var.function_app.cors_allowed_origins

  # BYO pattern: use existing resources if provided
  existing_service_plan_id    = var.function_app.existing_service_plan_id
  existing_storage_account_id = var.function_app.existing_storage_account_id

  app_settings = merge({
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = local.app_insights_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = local.app_insights_connection
  }, var.function_app.app_settings)

  # Pass tenant_id for Easy Auth
  tenant_id = var.tenant_id

  # Pass Easy Auth configuration if provided
  easy_auth = var.function_app.easy_auth != null ? {
    enabled                    = var.function_app.easy_auth.enabled
    client_id                  = var.function_app.easy_auth.client_id != "" ? var.function_app.easy_auth.client_id : module.entra_id_app.application_id
    client_secret_setting_name = var.function_app.easy_auth.client_secret_setting_name
    issuer                     = var.function_app.easy_auth.issuer
    tenant_id                  = var.function_app.easy_auth.tenant_id
    allowed_audiences          = var.function_app.easy_auth.allowed_audiences
    runtime_version            = var.function_app.easy_auth.runtime_version
    unauthenticated_action     = var.function_app.easy_auth.unauthenticated_action
    token_store_enabled        = var.function_app.easy_auth.token_store_enabled
    login_parameters           = var.function_app.easy_auth.login_parameters
    use_managed_identity       = var.function_app.easy_auth.use_managed_identity
  } : null

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

  plan_name = "plan-${var.project_name}-${var.environment}-web-easyauth-e2e"
  plan_sku  = var.web_app.plan_sku

  runtime_version = var.web_app.runtime_version
  startup_command = var.web_app.startup_command
  always_on       = var.web_app.always_on

  tenant_id = local.tenant_id
  # Use dynamically created Entra ID app client_id
  easy_auth = var.web_app.easy_auth != null ? merge(
    var.web_app.easy_auth,
    {
      client_id = module.entra_id_app.application_id
    }
  ) : null

  app_settings = merge({
    "WEBSITE_RUN_FROM_PACKAGE"              = "0"
    "WEBSITE_NODE_DEFAULT_VERSION"          = "~${var.web_app.runtime_version}"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"
    "API_BASE_URL"                          = var.web_app.api_base_url != "" ? var.web_app.api_base_url : module.function_app.function_app_url
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = local.app_insights_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = local.app_insights_connection
  }, var.web_app.app_settings)

  tags = local.common_tags
}
