# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "name" {
  description = "Base name of the Key Vault (will append random suffix if use_random_suffix is true)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}$", var.name))
    error_message = "Key Vault name must be 3-24 characters, start with a letter, and contain only alphanumeric and hyphens"
  }
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

# -----------------------------------------------------------------------------
# Key Vault Configuration
# -----------------------------------------------------------------------------

variable "sku_name" {
  description = "SKU of the Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU must be either standard or premium"
  }
}

variable "use_random_suffix" {
  description = "Append random suffix to Key Vault name to ensure global uniqueness"
  type        = bool
  default     = true
}

variable "enabled_for_deployment" {
  description = "Allow Azure Virtual Machines to retrieve certificates"
  type        = bool
  default     = false
}

variable "enabled_for_disk_encryption" {
  description = "Allow Azure Disk Encryption to retrieve secrets and unwrap keys"
  type        = bool
  default     = false
}

variable "enabled_for_template_deployment" {
  description = "Allow Azure Resource Manager to retrieve secrets during deployment"
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain deleted Key Vault and secrets (7-90 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days"
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection (prevents permanent deletion during retention period)"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow public network access to Key Vault"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Authorization Model
# -----------------------------------------------------------------------------

variable "enable_rbac_authorization" {
  description = "Use Azure RBAC for authorization (recommended). If false, uses access policies."
  type        = bool
  default     = true
}

variable "access_policies" {
  description = "Access policies (only used when enable_rbac_authorization = false)"
  type = map(object({
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "network_acls" {
  description = "Network ACLs for Key Vault"
  type = object({
    bypass                     = string
    default_action             = string
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics (optional)"
  type        = string
  default     = null
}

variable "diagnostic_log_categories" {
  description = "Log categories to enable for diagnostics"
  type        = list(string)
  default = [
    "AuditEvent",
    "AzurePolicyEvaluationDetails"
  ]
}

variable "diagnostic_metric_categories" {
  description = "Metric categories to enable for diagnostics"
  type        = list(string)
  default = [
    "AllMetrics"
  ]
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
