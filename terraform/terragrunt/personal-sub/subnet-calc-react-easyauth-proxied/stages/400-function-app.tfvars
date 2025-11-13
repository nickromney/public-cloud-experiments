# Stage 400 - Function App
# Adds Function App using UAI with managed identity auth

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
  react-easyauth = {
    display_name     = "Subnet Calculator React EasyAuth Proxy"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://subnet-calculator-react-easyauth-proxied"
    ]
    web_redirect_uris = [
      "https://func-subnet-calc-react-easyauth-proxied-api.azurewebsites.net/.auth/login/aad/callback",
      "https://web-subnet-calc-react-easyauth-proxied.azurewebsites.net/.auth/login/aad/callback"
    ]
  }
}

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

    # Managed Identity: UserAssigned with RBAC
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
# Web Apps (none yet)
# -----------------------------------------------------------------------------

web_apps = {}
