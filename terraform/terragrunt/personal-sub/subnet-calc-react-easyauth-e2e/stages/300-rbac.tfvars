# Stage 300 - RBAC
# Adds RBAC assignments (identity from 100 → storage from 200)

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

    # RBAC assignments for UAI
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
# Function Apps (none yet)
# -----------------------------------------------------------------------------

function_apps = {}

# -----------------------------------------------------------------------------
# Web Apps (none yet)
# -----------------------------------------------------------------------------

web_apps = {}
