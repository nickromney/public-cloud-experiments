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

  # BYO pattern: normalize and parse existing UAI resource ID
  existing_uai_id = try(
    var.existing_user_assigned_identity_id == null ? null : provider::azurerm::normalise_resource_id(var.existing_user_assigned_identity_id),
    null
  )

  # Parse UAI resource ID to extract name and resource group
  existing_uai = local.existing_uai_id != null ? provider::azurerm::parse_resource_id(local.existing_uai_id) : null
}

# Data source: fetch existing user-assigned identity if ID provided
data "azurerm_user_assigned_identity" "existing" {
  count = local.existing_uai_id != null ? 1 : 0

  name                = local.existing_uai.resource_name
  resource_group_name = local.existing_uai.resource_group_name
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

# Locals for storage authentication (must be before resource creation)
locals {
  # Storage authentication strategy (must be determinable at plan time for for_each)
  # Create UAI only when: type includes UserAssigned AND no existing UAI provided
  create_uai = var.managed_identity.enabled && contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) && local.existing_uai_id == null

  # Use MI for storage when we have a UAI (either existing or created)
  has_uai            = local.existing_uai_id != null || local.create_uai
  use_mi_for_storage = local.has_uai

  # Auto-determine RBAC assignment: assign roles when we CREATE the UAI, don't assign when using existing
  # But allow explicit override for delegated permissions scenarios
  should_assign_rbac = coalesce(var.assign_rbac_roles, local.create_uai)
}

# User-Assigned Managed Identity (created when managed identity is enabled)
# Must be created before Function App so we can grant it storage permissions
resource "azurerm_user_assigned_identity" "this" {
  count = local.create_uai ? 1 : 0

  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
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

  # User-assigned managed identity details (for storage authentication)
  # Use existing UAI if provided, otherwise use created UAI
  uai_client_id = local.existing_uai_id != null ? data.azurerm_user_assigned_identity.existing[0].client_id : (
    local.create_uai ? azurerm_user_assigned_identity.this[0].client_id : null
  )
  uai_principal_id = local.existing_uai_id != null ? data.azurerm_user_assigned_identity.existing[0].principal_id : (
    local.create_uai ? azurerm_user_assigned_identity.this[0].principal_id : null
  )
  uai_id = local.existing_uai_id != null ? local.existing_uai_id : (
    local.create_uai ? azurerm_user_assigned_identity.this[0].id : null
  )
}

# RBAC: Grant UAI storage permissions (Blob, Queue, Table Contributor)
# These are granted BEFORE Function App creation to avoid chicken-and-egg problem
# Controlled by assign_rbac_roles: defaults to true when creating UAI, false when using existing
# Override with explicit true if app team has delegated permissions on resources
resource "azurerm_role_assignment" "uai_storage_blob" {
  for_each = local.should_assign_rbac && local.has_uai ? { enabled = true } : {}

  scope                = local.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.uai_principal_id
}

resource "azurerm_role_assignment" "uai_storage_queue" {
  for_each = local.should_assign_rbac && local.has_uai ? { enabled = true } : {}

  scope                = local.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = local.uai_principal_id
}

resource "azurerm_role_assignment" "uai_storage_table" {
  for_each = local.should_assign_rbac && local.has_uai ? { enabled = true } : {}

  scope                = local.storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = local.uai_principal_id
}

# Wait for RBAC role assignments to propagate
# Azure role assignments can take up to 60 seconds to propagate
# Only wait when we assign permissions
resource "time_sleep" "rbac_propagation" {
  for_each = local.should_assign_rbac && local.has_uai ? { enabled = true } : {}

  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.uai_storage_blob,
    azurerm_role_assignment.uai_storage_queue,
    azurerm_role_assignment.uai_storage_table
  ]
}

# Linux Function App
resource "azurerm_linux_function_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = local.service_plan_id

  # Storage authentication: use managed identity if UAI is configured, otherwise use storage keys
  # UAI solves chicken-and-egg problem: identity and RBAC created before Function App
  storage_account_name       = local.storage_account_name
  storage_account_access_key = local.use_mi_for_storage ? null : local.storage_account_access_key

  # Explicit dependency: ensure RBAC roles are granted AND propagated before Function App tries to access storage
  depends_on = [
    azurerm_role_assignment.uai_storage_blob,
    azurerm_role_assignment.uai_storage_queue,
    azurerm_role_assignment.uai_storage_table,
    time_sleep.rbac_propagation
  ]

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
    # Application Insights connection string (identifies target App Insights instance)
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
    }, local.use_mi_for_storage ? {
    # Managed identity storage authentication
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "AzureWebJobsStorage__accountName"    = local.storage_account_name
    "AzureWebJobsStorage__credential"     = "managedidentity"
    "AzureWebJobsStorage__clientId"       = local.uai_client_id
  } : {}, var.app_settings)

  # Managed identity configuration
  dynamic "identity" {
    for_each = var.managed_identity.enabled ? [1] : []
    content {
      type = var.managed_identity.type
      # Include created UAI and any additional user-provided identity IDs
      identity_ids = contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? concat(
        local.uai_id != null ? [local.uai_id] : [],
        var.managed_identity.user_assigned_identity_ids
      ) : null
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
  # For system-assigned identity, use principal_id from Function App (known after apply)
  # For user-assigned identity, use principal_id from UAI (known before Function App creation)
  create_system_rbac  = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
  system_principal_id = local.create_system_rbac ? azurerm_linux_function_app.this.identity[0].principal_id : null
}

# RBAC: Monitoring Metrics Publisher for UAI (for Application Insights)
# Assigned before Function App creation
# Controlled by assign_rbac_roles: defaults to true when creating UAI, false when using existing
resource "azurerm_role_assignment" "uai_app_insights" {
  for_each = local.should_assign_rbac && local.has_uai ? { enabled = true } : {}

  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = local.uai_principal_id

  lifecycle {
    precondition {
      condition     = var.app_insights_id != null
      error_message = "app_insights_id must be provided when managed identity is enabled for RBAC assignments"
    }
  }
}

# RBAC: Monitoring Metrics Publisher for System-Assigned Identity (for Application Insights)
# Assigned after Function App creation
resource "azurerm_role_assignment" "system_app_insights" {
  for_each = local.create_system_rbac && !local.use_mi_for_storage ? { enabled = true } : {}

  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = local.system_principal_id

  lifecycle {
    precondition {
      condition     = var.app_insights_id != null
      error_message = "app_insights_id must be provided when managed identity is enabled for RBAC assignments"
    }
  }
}
