# Stage 900 - All (Complete Configuration)
# Superset of everything from stages 100-500
# Pattern: Use 900 for complete stacks in other deployments

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

environment         = "dev"
project_name        = "subnetcalc"
workload_name       = "subnet-calculator-react-easyauth-proxied"
resource_group_name = "rg-subnet-calc"

# -----------------------------------------------------------------------------
# User-Assigned Identities
# -----------------------------------------------------------------------------

user_assigned_identities = {
  funcapp = {
    name                = "id-func-subnet-calc-react-easyauth-proxied-api"
    resource_group_name = "rg-subnet-calc"
    location            = "uksouth"
  }
  webapp = {
    name                = "id-web-subnet-calc-react-easyauth-proxied"
    resource_group_name = "rg-subnet-calc"
    location            = "uksouth"
  }
}

# -----------------------------------------------------------------------------
# Service Plans
# -----------------------------------------------------------------------------

service_plans = {
  shared = {
    name     = "plan-subnetcalc-dev-easyauth-proxied"
    os_type  = "Linux"
    sku_name = "P0v3"
  }
}

# -----------------------------------------------------------------------------
# Storage Accounts (with RBAC)
# -----------------------------------------------------------------------------

storage_accounts = {
  funcapp = {
    name                     = "stsubnetcalcproxied"
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"

    rbac_assignments = {
      blob_contributor = {
        identity_key = "funcapp"
        role         = "Storage Blob Data Contributor"
      }
      file_contributor = {
        identity_key = "funcapp"
        role         = "Storage File Data SMB Share Contributor"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

log_analytics_workspaces = {}

shared_log_analytics_workspace_id = "/subscriptions/9800bc67-8c79-4be8-b6a7-9e536e752abf/resourceGroups/rg-subnet-calc/providers/Microsoft.OperationalInsights/workspaces/log-subnetcalc-shared-dev"

application_insights = {
  easyauth-proxied = {
    name             = "appi-subnetcalc-easyauth-proxied-dev"
    application_type = "web"
  }
}

# -----------------------------------------------------------------------------
# Entra ID App Registrations
# -----------------------------------------------------------------------------

entra_id_apps = {
  frontend = {
    display_name     = "Subnet Calculator React EasyAuth Frontend"
    sign_in_audience = "AzureADMyOrg"
    web_redirect_uris = [
      "https://web-subnet-calc-react-easyauth-proxied.azurewebsites.net/.auth/login/aad/callback"
    ]
    required_resource_access = [
      {
        # API app - allows frontend to request tokens for the API
        resource_app_id = "e65aae60-ea26-48e1-bc20-af9e1cff1dd7"
        resource_access = [
          {
            # user_impersonation scope
            id   = "15dcdbde-c98c-4442-8620-35fa793196da"
            type = "Scope"
          }
        ]
      }
    ]
  }

  api = {
    display_name     = "Subnet Calculator React EasyAuth API"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://subnet-calculator-react-easyauth-proxied-api"
    ]
    web_redirect_uris = [
      "https://func-subnet-calc-react-easyauth-proxied-api.azurewebsites.net/.auth/login/aad/callback"
    ]
    oauth2_permission_scopes = [
      {
        id                         = "15dcdbde-c98c-4442-8620-35fa793196da"
        admin_consent_display_name = "Access Subnet Calculator API"
        admin_consent_description  = "Allow the React frontend to call the Subnet Calculator API on behalf of the signed-in user."
        value                      = "user_impersonation"
      }
    ]
    app_roles = [
      {
        id                   = "b8f3c2a1-9d7e-4f6b-8c5a-1234567890ab"
        allowed_member_types = ["Application"]
        description          = "Allow applications and managed identities to access the Subnet Calculator API"
        display_name         = "API Access"
        value                = "API.Access"
      }
    ]
  }
}

entra_id_app_delegated_permissions = [
  {
    from_app_key = "frontend"
    to_app_key   = "api"
    scopes       = ["user_impersonation"]
  }
]

entra_id_app_role_assignments = [
  {
    app_key            = "api"
    app_role_value     = "API.Access"
    identity_key       = "webapp"
    assignment_purpose = "Allow Web App to call Function App using Managed Identity"
  }
]

# -----------------------------------------------------------------------------
# Function Apps
# -----------------------------------------------------------------------------

function_apps = {
  api = {
    name                          = "func-subnet-calc-react-easyauth-proxied-api"
    service_plan_key              = "shared"
    runtime                       = "python"
    runtime_version               = "3.11"
    storage_account_key           = "funcapp"
    storage_uses_managed_identity = true
    public_network_access_enabled = true
    app_insights_key              = "easyauth-proxied"

    cors_allowed_origins = [
      "https://web-subnet-calc-react-easyauth-proxied.azurewebsites.net"
    ]
    cors_support_credentials = true

    app_settings = {
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
      AUTH_METHOD                    = "azure_swa"
    }

    identity_type = "UserAssigned"
    identity_keys = ["funcapp"]

    easy_auth = {
      enabled       = true
      entra_app_key = "api"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-proxied-api"
      ]
      unauthenticated_action    = "Return401"
      token_store_enabled       = true
      additional_entra_app_keys = ["frontend"]
    }
  }
}

# -----------------------------------------------------------------------------
# Web Apps
# -----------------------------------------------------------------------------

web_apps = {
  frontend = {
    name             = "web-subnet-calc-react-easyauth-proxied"
    service_plan_key = "shared"
    runtime          = "node"
    runtime_version  = "22-lts"
    startup_file     = "node server.js"
    always_on        = true
    app_insights_key = "easyauth-proxied"

    app_settings = {
      STACK_NAME                     = "Subnet Calculator React (Easy Auth Proxy)"
      WEBSITE_NODE_DEFAULT_VERSION   = "~22"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
      WEBSITE_RUN_FROM_PACKAGE       = "0"
      API_BASE_URL                   = ""
      API_PROXY_ENABLED              = "true"
      PROXY_API_URL                  = "https://func-subnet-calc-react-easyauth-proxied-api.azurewebsites.net"
      PROXY_FORWARD_EASYAUTH_HEADERS = "false"
      AUTH_METHOD                    = "easyauth"
      AUTH_MODE                      = "easyauth"
      EASYAUTH_RESOURCE_ID           = "api://subnet-calculator-react-easyauth-proxied-api/.default"
    }

    identity_type = "UserAssigned"
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
