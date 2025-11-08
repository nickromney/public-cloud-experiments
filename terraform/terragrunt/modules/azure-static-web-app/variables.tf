# Azure Static Web App Module - Stack-Based Design
# Manages complete application stacks (SWA + Function App + dependencies)

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "project_name" {
  description = "Project identifier for resource naming (e.g., 'subnetcalc')"
  type        = string
  default     = "subnetcalc"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "stacks" {
  description = "Application stacks - each defines a complete deployment topology"
  type = map(object({
    # Optional resource names for import scenarios
    # When provided, uses these exact Azure names instead of generating new ones
    resource_names = optional(object({
      swa          = string
      function_app = string
      plan         = string
      storage      = string
    }))

    # Optional location overrides (for multi-region import scenarios)
    swa_location          = optional(string)
    function_app_location = optional(string)

    swa = object({
      sku            = string                      # Standard, Free
      custom_domain  = optional(string)            # Custom domain for SWA
      network_access = optional(string, "Enabled") # Enabled or Disabled

      # Authentication configuration
      # NOTE: These fields are planned for future implementation and are currently unused
      auth_enabled  = optional(bool, false)
      auth_provider = optional(string) # azuread, github, etc.
      allowed_roles = optional(list(string), [])
    })

    function_app = optional(object({
      plan_sku       = string           # FC1 (Flex Consumption), B1, S1, etc.
      python_version = string           # 3.11, 3.10, etc.
      auth_method    = string           # jwt, swa, none
      custom_domain  = optional(string) # Custom domain for Function App

      # Additional app settings (merged with defaults)
      app_settings = optional(map(string), {})

      # Site config overrides
      always_on = optional(bool) # null = auto-determine from plan_sku
    }))
  }))

  validation {
    condition = alltrue([
      for k, v in var.stacks : contains(["Standard", "Free"], v.swa.sku)
    ])
    error_message = "SWA sku must be either 'Standard' or 'Free'"
  }

  validation {
    condition = alltrue([
      for k, v in var.stacks : v.function_app == null || contains(
        ["jwt", "swa", "none"],
        v.function_app.auth_method
      )
    ])
    error_message = "Function App auth_method must be 'jwt', 'swa', or 'none'"
  }
}
