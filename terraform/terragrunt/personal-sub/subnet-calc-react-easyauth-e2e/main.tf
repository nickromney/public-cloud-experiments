# React Web App + Function App Stack
# Map-based architecture using atomic, composable modules

# -----------------------------------------------------------------------------
# Data Sources & Locals
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

locals {
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
    workload    = var.workload_name
  }, var.tags)
}

# -----------------------------------------------------------------------------
# Resource Groups (existing - using data source)
# -----------------------------------------------------------------------------

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# User-Assigned Identities (0-to-n pattern)
# -----------------------------------------------------------------------------

module "user_assigned_identities" {
  source = "../../modules/azure-user-assigned-identity"

  identities  = var.user_assigned_identities
  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Service Plans (0-to-n pattern)
# -----------------------------------------------------------------------------

module "service_plans" {
  source = "../../modules/azure-service-plan"

  # Convert map to module format
  service_plans = {
    for k, v in var.service_plans : k => {
      name                = v.name
      resource_group_name = data.azurerm_resource_group.main.name
      location            = data.azurerm_resource_group.main.location
      os_type             = v.os_type
      sku_name            = v.sku_name
      tags                = v.tags
    }
  }
  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Storage Accounts with RBAC (0-to-n pattern)
# -----------------------------------------------------------------------------

module "storage_accounts" {
  source = "../../modules/azure-storage-account"

  storage_accounts = {
    for k, v in var.storage_accounts : k => {
      name                          = v.name
      resource_group_name           = data.azurerm_resource_group.main.name
      location                      = data.azurerm_resource_group.main.location
      account_tier                  = v.account_tier
      account_replication_type      = v.account_replication_type
      account_kind                  = try(v.account_kind, "StorageV2")
      public_network_access_enabled = try(v.public_network_access_enabled, true)
      tags                          = try(v.tags, {})

      # RBAC assignments: map UAI keys to principal IDs
      rbac_assignments = {
        for assignment_key, assignment in try(v.rbac_assignments, {}) : assignment_key => {
          principal_id = module.user_assigned_identities.principal_ids[assignment.identity_key]
          role         = assignment.role
        }
      }
    }
  }

  common_tags = local.common_tags

  depends_on = [module.user_assigned_identities]
}

# -----------------------------------------------------------------------------
# Log Analytics & Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  for_each = var.log_analytics_workspaces

  name                = each.value.name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = try(each.value.sku, "PerGB2018")
  retention_in_days   = try(each.value.retention_in_days, 30)
  tags                = merge(local.common_tags, try(each.value.tags, {}))
}

resource "azurerm_application_insights" "this" {
  for_each = var.application_insights

  name                = each.value.name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.this[each.value.log_analytics_key].id
  application_type    = try(each.value.application_type, "web")
  tags                = merge(local.common_tags, try(each.value.tags, {}))
}

# -----------------------------------------------------------------------------
# Entra ID App Registration
# -----------------------------------------------------------------------------

module "entra_id_app" {
  source = "../../modules/azure-entra-id-app"

  for_each = var.entra_id_apps

  display_name      = each.value.display_name
  sign_in_audience  = try(each.value.sign_in_audience, "AzureADMyOrg")
  identifier_uris   = try(each.value.identifier_uris, [])
  web_redirect_uris = try(each.value.web_redirect_uris, [])
  spa_redirect_uris = try(each.value.spa_redirect_uris, [])
}

# -----------------------------------------------------------------------------
# Function Apps (0-to-n pattern)
# -----------------------------------------------------------------------------

module "function_apps" {
  source = "../../modules/azure-function-app"

  function_apps = {
    for k, v in var.function_apps : k => {
      name                = v.name
      resource_group_name = data.azurerm_resource_group.main.name
      location            = data.azurerm_resource_group.main.location
      service_plan_id     = module.service_plans.ids[v.service_plan_key]
      runtime             = v.runtime
      runtime_version     = v.runtime_version

      # Storage account (if using UAI)
      storage_account_name          = try(v.storage_account_key, null) != null ? module.storage_accounts.names[v.storage_account_key] : null
      storage_uses_managed_identity = try(v.storage_uses_managed_identity, false)

      # Network
      public_network_access_enabled = try(v.public_network_access_enabled, true)
      cors_allowed_origins          = try(v.cors_allowed_origins, null)

      # App Insights
      app_insights_connection_string = try(v.app_insights_key, null) != null ? azurerm_application_insights.this[v.app_insights_key].connection_string : null

      # App settings
      app_settings = try(v.app_settings, {})
      tags         = try(v.tags, {})

      # Identity (supports both created UAIs via identity_keys and BYO UAIs via identity_ids)
      identity = try(v.identity_type, null) != null ? {
        type = v.identity_type
        # Prefer identity_ids (BYO), fall back to identity_keys (created)
        identity_ids = length(try(v.identity_ids, [])) > 0 ? v.identity_ids : [for k in try(v.identity_keys, []) : module.user_assigned_identities.ids[k]]
      } : null

      # Easy Auth
      easy_auth = try(v.easy_auth, null) != null ? {
        enabled                = try(v.easy_auth.enabled, true)
        client_id              = module.entra_id_app[v.easy_auth.entra_app_key].application_id
        tenant_id              = local.tenant_id
        allowed_audiences      = try(v.easy_auth.allowed_audiences, [])
        unauthenticated_action = try(v.easy_auth.unauthenticated_action, "Return401")
        token_store_enabled    = try(v.easy_auth.token_store_enabled, true)
      } : null
    }
  }

  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Web Apps (0-to-n pattern)
# -----------------------------------------------------------------------------

module "web_apps" {
  source = "../../modules/azure-web-app"

  web_apps = {
    for k, v in var.web_apps : k => {
      name                = v.name
      resource_group_name = data.azurerm_resource_group.main.name
      location            = data.azurerm_resource_group.main.location
      service_plan_id     = module.service_plans.ids[v.service_plan_key]
      runtime             = v.runtime
      runtime_version     = v.runtime_version
      always_on           = try(v.always_on, true)

      # Network
      public_network_access_enabled = try(v.public_network_access_enabled, true)
      cors_allowed_origins          = try(v.cors_allowed_origins, null)

      # App settings (merge Application Insights connection string if provided)
      app_settings = merge(
        try(v.app_settings, {}),
        try(v.app_insights_key, null) != null ? {
          APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[v.app_insights_key].connection_string
        } : {}
      )
      tags = try(v.tags, {})

      # Identity (supports both created UAIs via identity_keys and BYO UAIs via identity_ids)
      identity = try(v.identity_type, null) != null ? {
        type = v.identity_type
        # Prefer identity_ids (BYO), fall back to identity_keys (created)
        identity_ids = length(try(v.identity_ids, [])) > 0 ? v.identity_ids : [for k in try(v.identity_keys, []) : module.user_assigned_identities.ids[k]]
      } : null

      # Easy Auth
      easy_auth = try(v.easy_auth, null) != null ? {
        enabled                = try(v.easy_auth.enabled, true)
        client_id              = module.entra_id_app[v.easy_auth.entra_app_key].application_id
        tenant_id              = local.tenant_id
        allowed_audiences      = try(v.easy_auth.allowed_audiences, [])
        unauthenticated_action = try(v.easy_auth.unauthenticated_action, "RedirectToLoginPage")
        default_provider       = try(v.easy_auth.default_provider, "azureactivedirectory")
        token_store_enabled    = try(v.easy_auth.token_store_enabled, true)
      } : null
    }
  }

  common_tags = local.common_tags
}
