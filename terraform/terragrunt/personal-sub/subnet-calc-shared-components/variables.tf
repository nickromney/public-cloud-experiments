# -----------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "subnetcalc"
}

variable "component_name" {
  description = "Component name for resource naming (e.g., shared, api, web)"
  type        = string
  default     = "shared"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

# -----------------------------------------------------------------------------
# Resource Group Configuration
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "create_resource_group" {
  description = "Create new resource group or use existing"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Log Analytics Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Log Analytics retention period in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Key Vault Configuration
# -----------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"
}

variable "key_vault_use_random_suffix" {
  description = "Append random suffix to Key Vault name"
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection on Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention period for Key Vault"
  type        = number
  default     = 90
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
