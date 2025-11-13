# Stage 200 - Storage
# Adds Storage Account (no RBAC yet)

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
# Storage Accounts (no RBAC yet)
# -----------------------------------------------------------------------------

storage_accounts = {
  funcapp = {
    name                     = "stsubnetcalcproxied"
    account_tier             = "Standard"
    account_replication_type = "LRS"
    account_kind             = "StorageV2"

    # No RBAC assignments yet
    rbac_assignments = {}
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
# Function Apps (none yet)
# -----------------------------------------------------------------------------

function_apps = {}

# -----------------------------------------------------------------------------
# Web Apps (none yet)
# -----------------------------------------------------------------------------

web_apps = {}
