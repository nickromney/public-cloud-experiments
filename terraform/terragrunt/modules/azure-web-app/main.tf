# Azure Web App Module
# Deploys Linux App Service with optional Easy Auth using managed identity

# Look up current Azure context for tenant_id when not provided
data "azurerm_client_config" "current" {}

locals {
  # Use provided tenant_id or fall back to current Azure context
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
}

# App Service Plan
resource "azurerm_service_plan" "this" {
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags
}

# Linux Web App with Managed Identity
resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true

  # Managed identity configuration
  dynamic "identity" {
    for_each = var.managed_identity.enabled ? [1] : []
    content {
      type         = var.managed_identity.type
      identity_ids = contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? var.managed_identity.user_assigned_identity_ids : null
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

# Local to extract principal_id for RBAC assignments
locals {
  # For system-assigned identity, use principal_id directly
  # For user-assigned, we'll grant permissions to the user-assigned identity (handled externally)
  # Create RBAC assignments when system-assigned identity is present (including when both system and user assigned)
  create_rbac_assignments = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
  principal_id            = var.managed_identity.enabled && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) ? azurerm_linux_web_app.this.identity[0].principal_id : null
}

# RBAC: Monitoring Metrics Publisher (for Application Insights)
resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  for_each = local.create_rbac_assignments ? { enabled = true } : {}

  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = local.principal_id

  lifecycle {
    precondition {
      condition     = var.app_insights_id != null
      error_message = "app_insights_id must be provided when managed identity is enabled for RBAC assignments"
    }
  }
}
