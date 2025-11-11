# Azure Function App Module
# Deploys Linux Function App with storage account and service plan
# Supports BYO (Bring Your Own) pattern for existing App Service Plans and Storage Accounts

# Look up current Azure context for tenant_id when not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  # BYO pattern: normalize and parse existing resource IDs
  existing_service_plan_id = try(
    var.existing_service_plan_id == null ? null : provider::azurerm::normalise_resource_id(var.existing_service_plan_id),
    null
  )

  existing_storage_account_id = try(
    var.existing_storage_account_id == null ? null : provider::azurerm::normalise_resource_id(var.existing_storage_account_id),
    null
  )

  # Parse resource IDs to extract name and resource group
  existing_service_plan    = local.existing_service_plan_id != null ? provider::azurerm::parse_resource_id(local.existing_service_plan_id) : null
  existing_storage_account = local.existing_storage_account_id != null ? provider::azurerm::parse_resource_id(local.existing_storage_account_id) : null
}

# Data source: fetch existing App Service Plan if ID provided
data "azurerm_service_plan" "existing" {
  count = local.existing_service_plan_id != null ? 1 : 0

  name                = local.existing_service_plan.resource_name
  resource_group_name = local.existing_service_plan.resource_group_name
}

# Data source: fetch existing Storage Account if ID provided
data "azurerm_storage_account" "existing" {
  count = local.existing_storage_account_id != null ? 1 : 0

  name                = local.existing_storage_account.resource_name
  resource_group_name = local.existing_storage_account.resource_group_name
}

# App Service Plan for Function App (only created if not using existing)
resource "azurerm_service_plan" "this" {
  count = local.existing_service_plan_id == null ? 1 : 0

  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = var.plan_name != ""
      error_message = "When 'existing_service_plan_id' is not provided, 'plan_name' must be specified."
    }
  }
}

# Storage Account for Function App (only created if not using existing)
resource "azurerm_storage_account" "this" {
  count = local.existing_storage_account_id == null ? 1 : 0

  name                       = var.storage_account_name != "" ? var.storage_account_name : lower(replace("st${var.name}", "-", ""))
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true
  tags                       = var.tags
}

# Locals to reference either existing or created resources
locals {
  service_plan_id = local.existing_service_plan_id != null ? local.existing_service_plan_id : azurerm_service_plan.this[0].id

  service_plan_name = local.existing_service_plan_id != null ? data.azurerm_service_plan.existing[0].name : azurerm_service_plan.this[0].name

  storage_account_id = local.existing_storage_account_id != null ? local.existing_storage_account_id : azurerm_storage_account.this[0].id

  storage_account_name = local.existing_storage_account_id != null ? data.azurerm_storage_account.existing[0].name : azurerm_storage_account.this[0].name

  storage_account_access_key = local.existing_storage_account_id != null ? data.azurerm_storage_account.existing[0].primary_access_key : azurerm_storage_account.this[0].primary_access_key
}

# Linux Function App
resource "azurerm_linux_function_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = local.service_plan_id

  # When using managed identity, only provide account name (no access key)
  # When not using managed identity, provide both name and key
  storage_account_name       = local.storage_account_name
  storage_account_access_key = var.managed_identity.enabled ? null : local.storage_account_access_key

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
    }, var.managed_identity.enabled ? {
    # Managed identity configuration for storage
    "AzureWebJobsStorage__accountName"     = local.storage_account_name
    "AzureWebJobsStorage__blobServiceUri"  = "https://${local.storage_account_name}.blob.core.windows.net"
    "AzureWebJobsStorage__queueServiceUri" = "https://${local.storage_account_name}.queue.core.windows.net"
    "AzureWebJobsStorage__tableServiceUri" = "https://${local.storage_account_name}.table.core.windows.net"
    # Application Insights connection string (identifies target App Insights instance)
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
  } : {}, var.app_settings)

  # Managed identity configuration
  dynamic "identity" {
    for_each = var.managed_identity.enabled ? [1] : []
    content {
      type         = var.managed_identity.type
      identity_ids = contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? var.managed_identity.user_assigned_identity_ids : null
    }
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

# Local to extract principal_id for RBAC assignments
locals {
  # For system-assigned identity, use principal_id directly
  # For user-assigned, we'll grant permissions to the user-assigned identity (handled externally)
  # Create RBAC assignments when system-assigned identity is present (including when both system and user assigned)
  create_rbac_assignments = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
  principal_id            = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? azurerm_linux_function_app.this.identity[0].principal_id : null
}

# RBAC: Storage Blob Data Owner (for AzureWebJobsStorage blobs)
resource "azurerm_role_assignment" "storage_blob_data_owner" {
  count = local.create_rbac_assignments ? 1 : 0

  scope                = local.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = local.principal_id
}

# RBAC: Storage Queue Data Contributor (for AzureWebJobsStorage queues)
resource "azurerm_role_assignment" "storage_queue_data_contributor" {
  count = local.create_rbac_assignments ? 1 : 0

  scope                = local.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = local.principal_id
}

# RBAC: Storage Table Data Contributor (for AzureWebJobsStorage tables)
resource "azurerm_role_assignment" "storage_table_data_contributor" {
  count = local.create_rbac_assignments ? 1 : 0

  scope                = local.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = local.principal_id
}

# RBAC: Monitoring Metrics Publisher (for Application Insights)
resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  count = local.create_rbac_assignments && var.app_insights_id != null ? 1 : 0

  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = local.principal_id
}
