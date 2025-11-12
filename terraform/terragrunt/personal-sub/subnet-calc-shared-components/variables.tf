# -----------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "pre", "np", "qa", "uat"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod, pre, np, qa, uat"
  }
}

# -----------------------------------------------------------------------------
# Resource Groups (0-to-n)
# Map-based pattern: empty map = use existing, populated map = create new
# -----------------------------------------------------------------------------

variable "resource_groups" {
  description = "Map of resource groups to create. Use empty map {} to reference existing RG via data source."
  type = map(object({
    name     = string
    location = string
    tags     = optional(map(string), {})
  }))
  default = {}
}

variable "existing_resource_group_name" {
  description = "Name of existing resource group to use when resource_groups map is empty"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Log Analytics Workspaces (0-to-n)
# Map-based pattern: empty map = don't create, populated map = create
# -----------------------------------------------------------------------------

variable "log_analytics_workspaces" {
  description = "Map of Log Analytics Workspaces to create. Use empty map {} to skip creation."
  type = map(object({
    name              = string
    sku               = optional(string, "PerGB2018")
    retention_in_days = optional(number, 30)
    tags              = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.log_analytics_workspaces :
      v.retention_in_days >= 30 && v.retention_in_days <= 730
    ])
    error_message = "Log retention must be between 30 and 730 days for all workspaces"
  }
}

# -----------------------------------------------------------------------------
# Key Vaults (0-to-n)
# Map-based pattern: empty map = don't create, populated map = create
# -----------------------------------------------------------------------------

variable "key_vaults" {
  description = "Map of Key Vaults to create. Use empty map {} to skip creation."
  type = map(object({
    name                        = string
    sku                         = optional(string, "standard")
    use_random_suffix           = optional(bool, true)
    purge_protection_enabled    = optional(bool, false)
    soft_delete_retention_days  = optional(number, 90)
    enable_rbac_authorization   = optional(bool, true)
    log_analytics_workspace_key = optional(string, null) # Key from log_analytics_workspaces map
    tags                        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.key_vaults :
      contains(["standard", "premium"], v.sku)
    ])
    error_message = "Key Vault SKU must be either 'standard' or 'premium' for all vaults"
  }

  validation {
    condition = alltrue([
      for k, v in var.key_vaults :
      v.soft_delete_retention_days >= 7 && v.soft_delete_retention_days <= 90
    ])
    error_message = "Key Vault soft delete retention must be between 7 and 90 days for all vaults"
  }
}

variable "grant_current_user_key_vault_access" {
  description = "Grant current user Key Vault Secrets Officer role on created Key Vaults"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
