# Entra ID App Registration Module
# Creates app registration for OAuth2/OpenID Connect authentication

data "azuread_client_config" "current" {}

# Microsoft Graph API
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}

# App Registration
resource "azuread_application" "this" {
  display_name     = var.display_name
  sign_in_audience = var.sign_in_audience
  owners           = concat([data.azuread_client_config.current.object_id], var.additional_owners)

  # Web application redirect URIs
  dynamic "web" {
    for_each = length(var.web_redirect_uris) > 0 ? [1] : []
    content {
      redirect_uris = var.web_redirect_uris

      implicit_grant {
        access_token_issuance_enabled = var.implicit_grant_access_token_enabled
        id_token_issuance_enabled     = var.implicit_grant_id_token_enabled
      }
    }
  }

  # SPA redirect URIs
  dynamic "single_page_application" {
    for_each = length(var.spa_redirect_uris) > 0 ? [1] : []
    content {
      redirect_uris = var.spa_redirect_uris
    }
  }

  # API configuration
  api {
    requested_access_token_version = var.requested_access_token_version

    # OAuth2 permission scopes (for APIM validation)
    dynamic "oauth2_permission_scope" {
      for_each = var.oauth2_permission_scopes
      content {
        id                         = oauth2_permission_scope.value.id
        admin_consent_description  = oauth2_permission_scope.value.admin_consent_description
        admin_consent_display_name = oauth2_permission_scope.value.admin_consent_display_name
        enabled                    = oauth2_permission_scope.value.enabled
        type                       = oauth2_permission_scope.value.type
        user_consent_description   = coalesce(oauth2_permission_scope.value.user_consent_description, oauth2_permission_scope.value.admin_consent_description)
        user_consent_display_name  = coalesce(oauth2_permission_scope.value.user_consent_display_name, oauth2_permission_scope.value.admin_consent_display_name)
        value                      = oauth2_permission_scope.value.value
      }
    }
  }

  # App roles (for APIM RBAC)
  dynamic "app_role" {
    for_each = var.app_roles
    content {
      id                   = app_role.value.id
      allowed_member_types = app_role.value.allowed_member_types
      description          = app_role.value.description
      display_name         = app_role.value.display_name
      enabled              = app_role.value.enabled
      value                = app_role.value.value
    }
  }

  # Identifier URIs (audience for APIM token validation)
  identifier_uris = var.identifier_uris

  # Required resource access (API permissions)
  dynamic "required_resource_access" {
    for_each = var.add_microsoft_graph_user_read ? [1] : []
    content {
      resource_app_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

      # User.Read delegated permission
      resource_access {
        id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
        type = "Scope"
      }
    }
  }

  # Custom API permissions
  dynamic "required_resource_access" {
    for_each = var.required_resource_access
    content {
      resource_app_id = required_resource_access.value.resource_app_id

      dynamic "resource_access" {
        for_each = required_resource_access.value.resource_access
        content {
          id   = resource_access.value.id
          type = resource_access.value.type
        }
      }
    }
  }
}

# Service Principal for the app
resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = var.app_role_assignment_required
  owners                       = concat([data.azuread_client_config.current.object_id], var.additional_owners)
}

# Client Secret
locals {
  create_secret     = var.create_client_secret ? { enabled = true } : {}
  store_in_keyvault = var.create_client_secret && var.key_vault_id != null ? { enabled = true } : {}
}

resource "azuread_application_password" "this" {
  for_each = local.create_secret

  application_id = azuread_application.this.id
  display_name   = var.client_secret_display_name
  end_date       = var.client_secret_end_date
}

# Store client secret in Key Vault (optional)
resource "azurerm_key_vault_secret" "client_secret" {
  for_each = local.store_in_keyvault

  name         = var.client_secret_kv_name != "" ? var.client_secret_kv_name : "${var.display_name}-client-secret"
  value        = azuread_application_password.this["enabled"].value
  key_vault_id = var.key_vault_id

  content_type = "application/json"

  tags = merge(var.tags, {
    app_id       = azuread_application.this.client_id
    display_name = var.display_name
  })
}
