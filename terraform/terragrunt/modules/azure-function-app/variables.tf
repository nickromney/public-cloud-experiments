variable "function_apps" {
  description = "Map of function apps to create"
  type = map(object({
    name                           = string
    resource_group_name            = string
    location                       = string
    service_plan_id                = string
    runtime                        = string                 # python, node, dotnet
    runtime_version                = string                 # e.g., "3.11", "20", "8.0"
    storage_account_name           = optional(string, null) # If null, Azure auto-creates
    storage_uses_managed_identity  = optional(bool, false)
    storage_account_access_key     = optional(string, null)
    public_network_access_enabled  = optional(bool, true)
    cors_allowed_origins           = optional(list(string), null)
    app_insights_connection_string = optional(string, null)
    app_insights_key               = optional(string, null)
    app_settings                   = optional(map(string), {})
    tags                           = optional(map(string), {})

    # Managed identity configuration
    identity = optional(object({
      type         = string # SystemAssigned, UserAssigned, or "SystemAssigned, UserAssigned"
      identity_ids = optional(list(string), [])
      client_id    = optional(string, null) # Client ID of the User-Assigned Identity (for UAMI storage access)
    }), null)

    # Easy Auth configuration
    easy_auth = optional(object({
      enabled                = optional(bool, true)
      client_id              = string
      tenant_id              = string
      tenant_auth_endpoint   = optional(string, null)
      allowed_audiences      = optional(list(string), [])
      unauthenticated_action = optional(string, "Return401")
      token_store_enabled    = optional(bool, true)
    }), null)
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all function apps"
  type        = map(string)
  default     = {}
}
