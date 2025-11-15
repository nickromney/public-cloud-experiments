# Stage 500 - Easy Auth + Managed Identity Proxying
# Enables Azure AD Easy Auth on both the Function App and Web App.
# The Web App obtains a token for the Function App using its user-assigned identity.

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

environment         = "dev"
project_name        = "authtest"
workload_name       = "webapp-auth-test-csharp"
resource_group_name = "rg-subnet-calc"

# -----------------------------------------------------------------------------
# User-Assigned Identities
# -----------------------------------------------------------------------------

user_assigned_identities = {
  webapp = {
    name                = "id-web-webapp-auth-test-csharp"
    resource_group_name = "rg-subnet-calc"
    location            = "uksouth"
  }
}

# -----------------------------------------------------------------------------
# Service Plans / Storage
# -----------------------------------------------------------------------------

service_plans    = {}
storage_accounts = {}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

log_analytics_workspaces = {}

shared_log_analytics_workspace_id = "/subscriptions/9800bc67-8c79-4be8-b6a7-9e536e752abf/resourceGroups/rg-subnet-calc/providers/Microsoft.OperationalInsights/workspaces/log-subnetcalc-shared-dev"

application_insights = {
  csharp = {
    name             = "appi-webapp-auth-test-csharp"
    application_type = "web"
  }
}

# -----------------------------------------------------------------------------
# Entra ID Applications
# -----------------------------------------------------------------------------

entra_id_apps = {
  frontend = {
    display_name     = "Web App Auth Test CSharp Frontend"
    sign_in_audience = "AzureADMyOrg"
    web_redirect_uris = [
      "https://web-csharp-test-f6fe93.azurewebsites.net/.auth/login/aad/callback"
    ]
  }

  api = {
    display_name     = "Web App Auth Test CSharp API"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://webapp-auth-test-csharp-api"
    ]
    web_redirect_uris = [
      "https://func-csharp-test-f6fe93.azurewebsites.net/.auth/login/aad/callback"
    ]
    oauth2_permission_scopes = [
      {
        id                         = "04b22760-f265-40f7-bb6f-caebbba2d878"
        admin_consent_display_name = "Access CSharp Test API"
        admin_consent_description  = "Allow callers to access the CSharp Function App on behalf of a signed-in user."
        value                      = "user_impersonation"
      }
    ]
    app_roles = [
      {
        id                   = "1a0a9237-ed53-4c62-b846-3f77c203c0b2"
        allowed_member_types = ["Application"]
        description          = "Allow applications and managed identities to access the API"
        display_name         = "API Access"
        value                = "API.Access"
      }
    ]
  }
}

entra_id_app_delegated_permissions = []

entra_id_app_role_assignments = [
  {
    app_key            = "api"
    app_role_value     = "API.Access"
    identity_key       = "webapp"
    assignment_purpose = "Allow the Web App's managed identity to call the Function App"
  }
]

# -----------------------------------------------------------------------------
# Function App
# -----------------------------------------------------------------------------

function_apps = {
  api = {
    name                          = "func-csharp-test-f6fe93"
    existing_service_plan_id      = "/subscriptions/9800bc67-8c79-4be8-b6a7-9e536e752abf/resourceGroups/rg-subnet-calc/providers/Microsoft.Web/serverFarms/plan-subnetcalc-dev-easyauth-proxied"
    runtime                       = "dotnet-isolated"
    runtime_version               = "9.0"
    storage_account_name          = "stcsharptestf6fe93"
    storage_uses_managed_identity = false
    public_network_access_enabled = true
    app_insights_key              = "csharp"

    cors_allowed_origins = [
      "https://web-csharp-test-f6fe93.azurewebsites.net"
    ]

    app_settings = {
      SCM_DO_BUILD_DURING_DEPLOYMENT         = "false"
      WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED = "1"
      AUTH_METHOD                            = "easyauth"
    }

    easy_auth = {
      enabled       = true
      entra_app_key = "api"
      allowed_audiences = [
        "api://webapp-auth-test-csharp-api"
      ]
      unauthenticated_action    = "Return401"
      token_store_enabled       = true
      additional_entra_app_keys = ["frontend"]
    }
  }
}

# -----------------------------------------------------------------------------
# Web App
# -----------------------------------------------------------------------------

web_apps = {
  frontend = {
    name                     = "web-csharp-test-f6fe93"
    existing_service_plan_id = "/subscriptions/9800bc67-8c79-4be8-b6a7-9e536e752abf/resourceGroups/rg-subnet-calc/providers/Microsoft.Web/serverFarms/plan-subnetcalc-dev-easyauth-proxied"
    runtime                  = "dotnet"
    runtime_version          = "9.0"
    startup_file             = "dotnet TestWebApp.dll"
    always_on                = true
    app_insights_key         = "csharp"

    app_settings = {
      SCM_DO_BUILD_DURING_DEPLOYMENT = "false"
      WEBSITE_RUN_FROM_PACKAGE       = "0"
      FUNCTION_APP_URL               = "https://func-csharp-test-f6fe93.azurewebsites.net"
      FUNCTION_APP_SCOPE             = "api://webapp-auth-test-csharp-api/.default"
      FUNCTION_APP_AUDIENCE          = "api://webapp-auth-test-csharp-api"
      USE_MANAGED_IDENTITY           = "true"
      AUTH_METHOD                    = "easyauth"
      EASYAUTH_RESOURCE_ID           = "api://webapp-auth-test-csharp-api"
    }

    identity_type = "SystemAssigned, UserAssigned"
    identity_keys = ["webapp"]

    easy_auth = {
      enabled                = true
      entra_app_key          = "frontend"
      allowed_audiences      = []
      unauthenticated_action = "RedirectToLoginPage"
      default_provider       = "azureactivedirectory"
      token_store_enabled    = true
    }
  }
}
