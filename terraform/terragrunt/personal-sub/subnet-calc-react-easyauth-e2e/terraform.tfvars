# Subnet Calculator React Web App + Function App - Easy Auth E2E
# Map-based configuration with atomic, composable modules
# Uses BYO (Bring Your Own) User-Assigned Managed Identity

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

environment         = "dev"
project_name        = "subnetcalc"
workload_name       = "subnet-calculator-react-easyauth-e2e"
resource_group_name = "rg-subnet-calc"

# -----------------------------------------------------------------------------
# User-Assigned Identities
# -----------------------------------------------------------------------------

user_assigned_identities = {
  funcapp = {
    name                = "id-func-subnet-calc-react-easyauth-e2e-api"
    resource_group_name = "rg-subnet-calc"
    location            = "uksouth"
  }
}

# -----------------------------------------------------------------------------
# Service Plans
# -----------------------------------------------------------------------------

service_plans = {
  shared = {
    name     = "plan-subnetcalc-dev-easyauth-e2e"
    os_type  = "Linux"
    sku_name = "P0v3" # Premium v3 - supports both Web Apps and Function Apps
  }
}

# -----------------------------------------------------------------------------
# Storage Accounts with RBAC
# -----------------------------------------------------------------------------

storage_accounts = {
  funcapp = {
    name                     = "stsubnetcalceasyauthe2e" # 24 chars max
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"

    # RBAC assignments for Function App managed identity
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

# Use shared Log Analytics workspace from shared-components stack
log_analytics_workspaces = {}

# Shared Log Analytics Workspace (referenced via dependency)
shared_log_analytics_workspace_id = "/subscriptions/9800bc67-8c79-4be8-b6a7-9e536e752abf/resourceGroups/rg-subnet-calc/providers/Microsoft.OperationalInsights/workspaces/log-subnetcalc-shared-dev"

application_insights = {
  easyauth-e2e = {
    name             = "appi-subnetcalc-easyauth-e2e-dev"
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
      "https://web-subnet-calc-react-easyauth-e2e.azurewebsites.net/.auth/login/aad/callback"
    ]
  }

  api = {
    display_name     = "Subnet Calculator React EasyAuth API"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://subnet-calculator-react-easyauth-e2e-api"
    ]
    web_redirect_uris = [
      "https://func-subnet-calc-react-easyauth-e2e-api.azurewebsites.net/.auth/login/aad/callback"
    ]
    oauth2_permission_scopes = [
      {
        id                         = "15dcdbde-c98c-4442-8620-35fa793196da"
        admin_consent_display_name = "Access Subnet Calculator API"
        admin_consent_description  = "Allow the React frontend to call the Subnet Calculator API on behalf of the signed-in user."
        value                      = "user_impersonation"
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

# -----------------------------------------------------------------------------
# Function Apps (using BYO UAI)
# -----------------------------------------------------------------------------

function_apps = {
  api = {
    name                          = "func-subnet-calc-react-easyauth-e2e-api"
    service_plan_key              = "shared"
    runtime                       = "python"
    runtime_version               = "3.11"
    storage_account_key           = "funcapp"
    storage_uses_managed_identity = true # Using managed identity with RBAC
    public_network_access_enabled = true
    app_insights_key              = "easyauth-e2e"

    cors_allowed_origins = [
      "https://web-subnet-calc-react-easyauth-e2e.azurewebsites.net"
    ]
    cors_support_credentials = true

    app_settings = {
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
      AUTH_METHOD                    = "azure_ad"
    }

    # Managed Identity: UserAssigned with RBAC over storage account
    identity_type = "UserAssigned"
    identity_keys = ["funcapp"]

    # Easy Auth
    easy_auth = {
      enabled       = true
      entra_app_key = "api"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-e2e-api"
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
    name             = "web-subnet-calc-react-easyauth-e2e"
    service_plan_key = "shared"
    runtime          = "node"
    runtime_version  = "22-lts"
    startup_file     = "node server.js"
    always_on        = true
    app_insights_key = "easyauth-e2e"

    app_settings = {
      STACK_NAME                     = "Subnet Calculator React (Easy Auth E2E)"
      WEBSITE_NODE_DEFAULT_VERSION   = "~22"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
      WEBSITE_RUN_FROM_PACKAGE       = "0"
      API_BASE_URL                   = "https://func-subnet-calc-react-easyauth-e2e-api.azurewebsites.net"
      AUTH_METHOD                    = "easyauth"
      AUTH_MODE                      = "easyauth"
      EASYAUTH_RESOURCE_ID           = "api://subnet-calculator-react-easyauth-e2e-api"
    }

    # Managed Identity: SystemAssigned
    identity_type = "SystemAssigned"

    # Easy Auth
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
