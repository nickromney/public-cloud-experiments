# Azure Function App Module
# Map-based pattern: creates 0-to-n function apps
# Dependencies (service plan, storage, UAI) must be created separately
# Storage account is OPTIONAL - if not provided, Azure auto-creates one

locals {
  # Build app settings with managed identity storage configuration when needed
  function_app_settings = {
    for key, app in var.function_apps : key => merge(
      # Base app settings from configuration
      try(app.app_settings, {}),

      # Add managed identity storage settings when using UAMI
      try(app.storage_uses_managed_identity, false) && try(app.identity.type, "") == "UserAssigned" ? {
        "AzureWebJobsStorage__credential" = "managedidentity"
        "AzureWebJobsStorage__clientId"   = try(app.identity.client_id, null)
      } : {}
    )
  }
}

resource "azurerm_linux_function_app" "this" {
  for_each = var.function_apps

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  service_plan_id     = each.value.service_plan_id

  # Storage configuration (optional)
  # If storage_account_name is provided: use it with managed identity or connection string
  # If not provided: Azure auto-creates storage account (connection string mode)
  storage_account_name          = try(each.value.storage_account_name, null)
  storage_uses_managed_identity = try(each.value.storage_uses_managed_identity, false)

  # If using auto-created storage or explicit connection string, provide access key
  storage_account_access_key = try(each.value.storage_account_access_key, null)

  # Network configuration
  public_network_access_enabled = try(each.value.public_network_access_enabled, true)

  # Security defaults (match Azure CLI deployment)
  builtin_logging_enabled                        = try(each.value.builtin_logging_enabled, false)
  client_certificate_mode                        = try(each.value.client_certificate_mode, "Required")
  ftp_publish_basic_authentication_enabled       = try(each.value.ftp_publish_basic_authentication_enabled, false)
  webdeploy_publish_basic_authentication_enabled = try(each.value.webdeploy_publish_basic_authentication_enabled, false)

  # Runtime configuration
  site_config {
    # Python runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "python" ? [1] : []
      content {
        python_version = each.value.runtime_version
      }
    }

    # Node.js runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "node" ? [1] : []
      content {
        node_version = each.value.runtime_version
      }
    }

    # .NET runtime (in-process)
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "dotnet" ? [1] : []
      content {
        dotnet_version = each.value.runtime_version
      }
    }

    # .NET Isolated runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "dotnet-isolated" ? [1] : []
      content {
        dotnet_version              = each.value.runtime_version
        use_dotnet_isolated_runtime = true
      }
    }

    # Security settings (match Azure CLI deployment defaults)
    ftps_state    = try(each.value.ftps_state, "FtpsOnly")
    http2_enabled = try(each.value.http2_enabled, true)

    # CORS configuration
    dynamic "cors" {
      for_each = try(each.value.cors_allowed_origins, null) != null ? [1] : []
      content {
        allowed_origins     = each.value.cors_allowed_origins
        support_credentials = try(each.value.cors_support_credentials, false)
      }
    }

    # Application Insights
    application_insights_connection_string = try(each.value.app_insights_connection_string, null)
    application_insights_key               = try(each.value.app_insights_key, null)
  }

  # App settings (includes managed identity storage settings when applicable)
  app_settings = local.function_app_settings[each.key]

  # Managed Identity (optional)
  dynamic "identity" {
    for_each = try(each.value.identity, null) != null ? [1] : []
    content {
      type         = each.value.identity.type
      identity_ids = try(each.value.identity.identity_ids, [])
    }
  }

  # Easy Auth / Authentication (optional)
  dynamic "auth_settings_v2" {
    for_each = try(each.value.easy_auth, null) != null ? [1] : []
    content {
      auth_enabled           = try(each.value.easy_auth.enabled, true)
      unauthenticated_action = try(each.value.easy_auth.unauthenticated_action, "Return401")

      # Excluded paths - critical for Function Apps to allow runtime management endpoints
      # Must exclude /admin/* for function registration and /runtime/* for webhooks
      excluded_paths = try(each.value.easy_auth.excluded_paths, ["/admin/*", "/runtime/*"])

      login {
        token_store_enabled = try(each.value.easy_auth.token_store_enabled, true)
      }

      dynamic "active_directory_v2" {
        for_each = try(each.value.easy_auth.client_id, null) != null ? [1] : []
        content {
          client_id            = each.value.easy_auth.client_id
          tenant_auth_endpoint = coalesce(each.value.easy_auth.tenant_auth_endpoint, "https://login.microsoftonline.com/${each.value.easy_auth.tenant_id}/v2.0")
          allowed_audiences    = try(each.value.easy_auth.allowed_audiences, [])
        }
      }
    }
  }

  tags = merge(var.common_tags, try(each.value.tags, {}))

  lifecycle {
    ignore_changes = [
      tags["hidden-link: /app-insights-resource-id"],
    ]
  }
}
