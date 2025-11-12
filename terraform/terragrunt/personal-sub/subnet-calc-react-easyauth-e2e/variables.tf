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

variable "application_insights" {
  description = "Map of Application Insights instances to create"
  type = map(object({
    name              = string
    log_analytics_key = string # Key from log_analytics_workspaces map
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
    display_name      = string
    sign_in_audience  = optional(string, "AzureADMyOrg")
    identifier_uris   = optional(list(string), [])
    web_redirect_uris = optional(list(string), [])
    spa_redirect_uris = optional(list(string), [])
  }))
  default = {}
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
      unauthenticated_action = optional(string, "Return401")
      token_store_enabled    = optional(bool, true)
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
