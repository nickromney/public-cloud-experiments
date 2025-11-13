# Stage 500 - Web App
# Adds Web App to complete the stack

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
    sku_name = "P0v3"
  }
}

# -----------------------------------------------------------------------------
# Storage Accounts (with RBAC)
# -----------------------------------------------------------------------------

storage_accounts = {
  funcapp = {
    name                     = "stsubnetcalceasyauthe2e"
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
  easyauth-e2e = {
    name             = "appi-subnetcalc-easyauth-e2e-dev"
    application_type = "web"
  }
}

# -----------------------------------------------------------------------------
# Entra ID App Registrations
# -----------------------------------------------------------------------------

entra_id_apps = {
  react-easyauth = {
    display_name     = "Subnet Calculator React E2E"
    sign_in_audience = "AzureADMyOrg"
    identifier_uris = [
      "api://subnet-calculator-react-easyauth-e2e"
    ]
    web_redirect_uris = [
      "https://func-subnet-calc-react-easyauth-e2e-api.azurewebsites.net/.auth/login/aad/callback",
      "https://web-subnet-calc-react-easyauth-e2e.azurewebsites.net/.auth/login/aad/callback"
    ]
  }
}

# -----------------------------------------------------------------------------
# Function Apps
# -----------------------------------------------------------------------------

function_apps = {
  api = {
    name                          = "func-subnet-calc-react-easyauth-e2e-api"
    service_plan_key              = "shared"
    runtime                       = "python"
    runtime_version               = "3.11"
    storage_account_key           = "funcapp"
    storage_uses_managed_identity = true
    public_network_access_enabled = true
    app_insights_key              = "easyauth-e2e"

    cors_allowed_origins = [
      "https://web-subnet-calc-react-easyauth-e2e.azurewebsites.net"
    ]

    app_settings = {
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    }

    identity_type = "UserAssigned"
    identity_keys = ["funcapp"]

    easy_auth = {
      enabled       = true
      entra_app_key = "react-easyauth"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-e2e",
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
      EASYAUTH_RESOURCE_ID           = "api://subnet-calculator-react-easyauth-e2e"
    }

    identity_type = "SystemAssigned"

    easy_auth = {
      enabled       = true
      entra_app_key = "react-easyauth"
      allowed_audiences = [
        "api://subnet-calculator-react-easyauth-e2e"
      ]
      unauthenticated_action = "RedirectToLoginPage"
      default_provider       = "azureactivedirectory"
      token_store_enabled    = true
    }
  }
}
