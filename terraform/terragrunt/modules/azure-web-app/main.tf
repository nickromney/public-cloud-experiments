# Azure Web App Module
# Deploys Linux App Service with optional Easy Auth using managed identity
# Supports BYO (Bring Your Own) pattern for existing App Service Plans

# Look up current Azure context for tenant_id when not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  # BYO pattern: normalize and parse existing resource ID
  existing_service_plan_id = try(
    var.existing_service_plan_id == null ? null : provider::azurerm::normalise_resource_id(var.existing_service_plan_id),
    null
  )

  # Parse resource ID to extract name and resource group
  existing_service_plan = local.existing_service_plan_id != null ? provider::azurerm::parse_resource_id(local.existing_service_plan_id) : null

  # BYO pattern: normalize and parse existing UAI resource ID
  existing_uai_id = try(
    var.existing_user_assigned_identity_id == null ? null : provider::azurerm::normalise_resource_id(var.existing_user_assigned_identity_id),
    null
  )

  # Parse UAI resource ID to extract name and resource group
  existing_uai = local.existing_uai_id != null ? provider::azurerm::parse_resource_id(local.existing_uai_id) : null

  # UAI creation: create only when type includes UserAssigned AND no existing UAI provided
  create_uai = var.managed_identity.enabled && contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) && local.existing_uai_id == null

  # Auto-determine RBAC assignment: assign roles when we CREATE the UAI, don't assign when using existing
  # But allow explicit override for delegated permissions scenarios
  should_assign_rbac = coalesce(var.assign_rbac_roles, local.create_uai)
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

# App Service Plan for Web App (only created if not using existing)
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

# Locals to reference either existing or created service plan
locals {
  service_plan_id = local.existing_service_plan_id != null ? local.existing_service_plan_id : azurerm_service_plan.this[0].id
}

# User-Assigned Managed Identity (created when managed identity is enabled with UserAssigned type)
resource "azurerm_user_assigned_identity" "this" {
  count = local.create_uai ? 1 : 0

  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Locals for UAI details
# Use existing UAI if provided, otherwise use created UAI
locals {
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

# RBAC: Monitoring Metrics Publisher for UAI (for Application Insights)
# Assigned before Web App creation
# Controlled by assign_rbac_roles: defaults to true when creating UAI, false when using existing
resource "azurerm_role_assignment" "uai_app_insights" {
  for_each = local.should_assign_rbac && (local.existing_uai_id != null || local.create_uai) ? { enabled = true } : {}

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

# Linux Web App with Managed Identity
resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = local.service_plan_id
  https_only          = true

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

  site_config {
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    always_on              = var.always_on
    vnet_route_all_enabled = false
    default_documents      = var.default_documents
    app_command_line       = var.startup_command

    application_stack {
      node_version = var.runtime_version
    }
  }

  app_settings = var.app_settings

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
        tenant_auth_endpoint                 = auth_settings_v2.value.issuer != "" ? auth_settings_v2.value.issuer : "https://login.microsoftonline.com/${coalesce(auth_settings_v2.value.tenant_id, local.tenant_id)}/v2.0"
        allowed_audiences                    = auth_settings_v2.value.allowed_audiences
        login_parameters                     = auth_settings_v2.value.login_parameters
        client_secret_setting_name           = auth_settings_v2.value.client_secret_setting_name != "" ? auth_settings_v2.value.client_secret_setting_name : null
        client_secret_certificate_thumbprint = null
      }
    }
  }

  tags = var.tags
}

# Local to extract principal_id for system-assigned RBAC assignments
locals {
  # For system-assigned identity, use principal_id from Web App (known after apply)
  # For user-assigned identity, use principal_id from UAI (known before Web App creation)
  create_system_rbac  = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
  system_principal_id = local.create_system_rbac ? azurerm_linux_web_app.this.identity[0].principal_id : null
}

# RBAC: Monitoring Metrics Publisher for System-Assigned Identity (for Application Insights)
# Assigned after Web App creation
resource "azurerm_role_assignment" "system_app_insights" {
  for_each = local.create_system_rbac && !local.create_uai ? { enabled = true } : {}

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
