variable "web_apps" {
  description = "Map of web apps to create"
  type = map(object({
    name                           = string
    resource_group_name            = string
    location                       = string
    service_plan_id                = string
    runtime                        = string                 # node, python, dotnet
    runtime_version                = string                 # e.g., "20-lts", "3.11", "8.0"
    startup_file                   = optional(string, null) # Startup command (e.g., "node server.js")
    always_on                      = optional(bool, true)
    https_only                     = optional(bool, true)
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
    }), null)

    # Easy Auth configuration
    easy_auth = optional(object({
      enabled                = optional(bool, true)
      client_id              = string
      tenant_id              = string
      tenant_auth_endpoint   = optional(string, null)
      allowed_audiences      = optional(list(string), [])
      unauthenticated_action = optional(string, "RedirectToLoginPage")
      default_provider       = optional(string, "azureactivedirectory")
      token_store_enabled    = optional(bool, true)
    }), null)
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all web apps"
  type        = map(string)
  default     = {}
}
