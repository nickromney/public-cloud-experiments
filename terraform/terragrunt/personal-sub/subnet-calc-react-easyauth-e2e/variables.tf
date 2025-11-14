# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "workload_name" {
  description = "Workload name for tagging"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID (optional - defaults to current)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# User-Assigned Identities (0-to-n)
# -----------------------------------------------------------------------------

variable "user_assigned_identities" {
  description = "Map of user-assigned identities to create"
  type = map(object({
    name                = string
    resource_group_name = string
    location            = string
    tags                = optional(map(string), {})
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Service Plans (0-to-n)
# -----------------------------------------------------------------------------

variable "service_plans" {
  description = "Map of service plans to create"
  type = map(object({
    name     = string
    os_type  = string
    sku_name = string
    tags     = optional(map(string), {})
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Storage Accounts (0-to-n)
# -----------------------------------------------------------------------------

variable "storage_accounts" {
  description = "Map of storage accounts to create"
  type = map(object({
    name                          = string
    account_tier                  = string
    account_replication_type      = string
    account_kind                  = optional(string, "StorageV2")
    public_network_access_enabled = optional(bool, true)
    tags                          = optional(map(string), {})

    # RBAC assignments: map of identity_key => role
    rbac_assignments = optional(map(object({
      identity_key = string # Key from user_assigned_identities map
      role         = string # e.g., "Storage Blob Data Contributor"
    })), {})
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Observability (Log Analytics + App Insights)
# -----------------------------------------------------------------------------

variable "log_analytics_workspaces" {
  description = "Map of Log Analytics workspaces to create"
  type = map(object({
    name              = string
    sku               = optional(string, "PerGB2018")
    retention_in_days = optional(number, 30)
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "shared_log_analytics_workspace_id" {
  description = "Resource ID of shared Log Analytics workspace (from shared-components stack)"
  type        = string
  default     = ""
}

variable "application_insights" {
  description = "Map of Application Insights instances to create"
  type = map(object({
    name              = string
    log_analytics_key = optional(string, null) # Key from log_analytics_workspaces map (optional if using shared workspace)
    application_type  = optional(string, "web")
    tags              = optional(map(string), {})
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Entra ID App Registrations (0-to-n)
# -----------------------------------------------------------------------------

variable "entra_id_apps" {
  description = "Map of Entra ID app registrations to create"
  type = map(object({
    display_name                        = string
    sign_in_audience                    = optional(string, "AzureADMyOrg")
    identifier_uris                     = optional(list(string), [])
    web_redirect_uris                   = optional(list(string), [])
    spa_redirect_uris                   = optional(list(string), [])
    implicit_grant_access_token_enabled = optional(bool, true)
    implicit_grant_id_token_enabled     = optional(bool, true)
    requested_access_token_version      = optional(number, 2)
    add_microsoft_graph_user_read       = optional(bool, true)
    oauth2_permission_scopes = optional(list(object({
      id                         = string
      admin_consent_description  = string
      admin_consent_display_name = string
      value                      = string
      type                       = optional(string, "User")
      enabled                    = optional(bool, true)
      user_consent_description   = optional(string)
      user_consent_display_name  = optional(string)
    })), [])
    required_resource_access = optional(list(object({
      resource_app_id = string
      resource_access = list(object({
        id   = string
        type = string
      }))
    })), [])
    app_roles = optional(list(object({
      id                   = string
      allowed_member_types = list(string)
      description          = string
      display_name         = string
      value                = string
      enabled              = optional(bool, true)
    })), [])
    additional_owners          = optional(list(string), [])
    create_client_secret       = optional(bool, false)
    client_secret_display_name = optional(string, "terraform-generated")
    client_secret_end_date     = optional(string, null)
    key_vault_id               = optional(string, null)
    client_secret_kv_name      = optional(string, "")
    tags                       = optional(map(string), {})
  }))
  default = {}
}

variable "entra_id_app_delegated_permissions" {
  description = "Delegated permissions to grant between Entra ID applications (from -> to, scoped list)."
  type = list(object({
    from_app_key = string
    to_app_key   = string
    scopes       = list(string)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Function Apps (0-to-n)
# -----------------------------------------------------------------------------

variable "function_apps" {
  description = "Map of function apps to create"
  type = map(object({
    name                          = string
    service_plan_key              = string                 # Key from service_plans map
    runtime                       = string                 # python, node, dotnet
    runtime_version               = string                 # e.g., "3.11", "20", "8.0"
    storage_account_key           = optional(string, null) # Key from storage_accounts map (null = auto-create)
    storage_uses_managed_identity = optional(bool, false)
    public_network_access_enabled = optional(bool, true)
    cors_allowed_origins          = optional(list(string), null)
    cors_support_credentials      = optional(bool, false)
    app_insights_key              = optional(string, null) # Key from application_insights map
    app_settings                  = optional(map(string), {})
    tags                          = optional(map(string), {})

    # Identity configuration
    identity_type = optional(string, null)     # "SystemAssigned", "UserAssigned", or "SystemAssigned, UserAssigned"
    identity_keys = optional(list(string), []) # List of keys from user_assigned_identities map (for created UAIs)
    identity_ids  = optional(list(string), []) # List of UAI resource IDs (for BYO UAIs)

    # Easy Auth configuration
    easy_auth = optional(object({
      enabled                   = optional(bool, true)
      entra_app_key             = string # Key from entra_id_apps map
      allowed_audiences         = optional(list(string), [])
      unauthenticated_action    = optional(string, "Return401")
      token_store_enabled       = optional(bool, true)
      additional_entra_app_keys = optional(list(string), [])
    }), null)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Web Apps (0-to-n)
# -----------------------------------------------------------------------------

variable "web_apps" {
  description = "Map of web apps to create"
  type = map(object({
    name                          = string
    service_plan_key              = string # Key from service_plans map
    runtime                       = string # node, python, dotnet
    runtime_version               = string # e.g., "20-lts", "3.11", "8.0"
    startup_file                  = optional(string, null)
    always_on                     = optional(bool, true)
    public_network_access_enabled = optional(bool, true)
    cors_allowed_origins          = optional(list(string), null)
    app_insights_key              = optional(string, null) # Key from application_insights map
    app_settings                  = optional(map(string), {})
    tags                          = optional(map(string), {})

    # Identity configuration
    identity_type = optional(string, null)     # "SystemAssigned", "UserAssigned", or "SystemAssigned, UserAssigned"
    identity_keys = optional(list(string), []) # List of keys from user_assigned_identities map (for created UAIs)
    identity_ids  = optional(list(string), []) # List of UAI resource IDs (for BYO UAIs)

    # Easy Auth configuration
    easy_auth = optional(object({
      enabled                = optional(bool, true)
      entra_app_key          = string # Key from entra_id_apps map
      allowed_audiences      = optional(list(string), [])
      unauthenticated_action = optional(string, "RedirectToLoginPage")
      default_provider       = optional(string, "azureactivedirectory")
      token_store_enabled    = optional(bool, true)
    }), null)
  }))
  default = {}
}
