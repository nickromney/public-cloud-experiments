# Azure Web App (Linux) Module
# Map-based pattern: creates 0-to-n web apps
# Dependencies (service plan, UAI) must be created separately

resource "azurerm_linux_web_app" "this" {
  for_each = var.web_apps

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  service_plan_id     = each.value.service_plan_id

  # Network configuration
  public_network_access_enabled = try(each.value.public_network_access_enabled, true)
  https_only                    = try(each.value.https_only, false)

  # Security defaults (match Azure CLI deployment)
  client_affinity_enabled                        = try(each.value.client_affinity_enabled, true)
  ftp_publish_basic_authentication_enabled       = try(each.value.ftp_publish_basic_authentication_enabled, false)
  webdeploy_publish_basic_authentication_enabled = try(each.value.webdeploy_publish_basic_authentication_enabled, false)

  # Site configuration
  site_config {
    app_command_line = try(each.value.startup_file, null)

    # Node.js runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "node" ? [1] : []
      content {
        node_version = each.value.runtime_version
      }
    }

    # Python runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "python" ? [1] : []
      content {
        python_version = each.value.runtime_version
      }
    }

    # .NET runtime
    dynamic "application_stack" {
      for_each = try(each.value.runtime, null) == "dotnet" ? [1] : []
      content {
        dotnet_version = each.value.runtime_version
      }
    }

    # Always on (keep app loaded)
    always_on = try(each.value.always_on, true)

    # Security settings (match Azure CLI deployment defaults)
    ftps_state    = try(each.value.ftps_state, "FtpsOnly")
    http2_enabled = try(each.value.http2_enabled, true)

    # CORS configuration
    dynamic "cors" {
      for_each = try(each.value.cors_allowed_origins, null) != null ? [1] : []
      content {
        allowed_origins = each.value.cors_allowed_origins
      }
    }
  }

  # App settings
  app_settings = try(each.value.app_settings, {})

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
      unauthenticated_action = try(each.value.easy_auth.unauthenticated_action, "RedirectToLoginPage")
      default_provider       = try(each.value.easy_auth.default_provider, "azureactivedirectory")

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
