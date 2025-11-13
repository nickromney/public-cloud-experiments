# Subnet Calculator React Web App + Function App - Easy Auth Proxy
# Map-based configuration with atomic, composable modules
# Uses BYO (Bring Your Own) User-Assigned Managed Identity

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
}

# -----------------------------------------------------------------------------
# Service Plans
# -----------------------------------------------------------------------------

service_plans = {
  shared = {
    name     = "plan-subnetcalc-dev-easyauth-proxied"
    os_type  = "Linux"
    sku_name = "P0v3" # Premium v3 - supports both Web Apps and Function Apps
  }
}

# -----------------------------------------------------------------------------
# Storage Accounts with RBAC
# -----------------------------------------------------------------------------

storage_accounts = {
  funcapp = {
    name                     = "stsubnetcalcproxied" # 24 chars max
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
  easyauth-proxied = {
    name             = "appi-subnetcalc-easyauth-proxied-dev"
    application_type = "web"
  }
}

# -----------------------------------------------------------------------------
# Entra ID App Registrations
# -----------------------------------------------------------------------------

entra_id_apps = {
  react-easyauth = {
    display_name     = "Subnet Calculator React EasyAuth Proxy"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://subnet-calculator-react-easyauth-proxied"
    ]
  }
}

# -----------------------------------------------------------------------------
# Function Apps (using BYO UAI)
# -----------------------------------------------------------------------------

function_apps = {
  api = {
    name                          = "func-subnet-calc-react-easyauth-proxied-api"
    service_plan_key              = "shared"
    runtime                       = "python"
    runtime_version               = "3.11"
    storage_account_key           = "funcapp"
    storage_uses_managed_identity = true # Using managed identity with RBAC
    public_network_access_enabled = true
    app_insights_key              = "easyauth-proxied"

    cors_allowed_origins = [
      "https://web-subnet-calc-react-easyauth-proxied.azurewebsites.net"
    ]

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
      entra_app_key = "react-easyauth"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-proxied",
        "d62b2e8f-a9a7-4aa4-b303-a861b0e3885e"
      ]
      unauthenticated_action = "Return401"
      token_store_enabled    = true
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
      PROXY_API_URL                  = "https://func-subnet-calc-react-easyauth-proxied-api.azurewebsites.net"
      PROXY_FORWARD_EASYAUTH_HEADERS = "true"
      AUTH_METHOD                    = "easyauth"
      AUTH_MODE                      = "easyauth"
    }

    # Managed Identity: SystemAssigned
    identity_type = "SystemAssigned"

    # Easy Auth
    easy_auth = {
      enabled       = true
      entra_app_key = "react-easyauth"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-proxied"
      ]
      unauthenticated_action = "RedirectToLoginPage"
      default_provider       = "azureactivedirectory"
      token_store_enabled    = true
    }
  }
}
