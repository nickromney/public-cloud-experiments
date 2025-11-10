# -----------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------

variable "location" {
  description = "Azure region for resources"
  type        = string

  validation {
    condition     = contains(["uksouth", "ukwest", "eastus", "eastus2", "westeurope"], var.location)
    error_message = "Location must be one of: uksouth, ukwest, eastus, eastus2, westeurope"
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "subnetcalc"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters, lowercase alphanumeric and hyphens only"
  }
}

variable "component_name" {
  description = "Component name for resource naming (e.g., shared, api, web)"
  type        = string
  default     = "shared"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.component_name))
    error_message = "Component name must be 3-24 characters, lowercase alphanumeric and hyphens only"
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "pre", "np", "qa", "uat"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod, pre, np, qa, uat"
  }
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

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days"
  }
}

# -----------------------------------------------------------------------------
# Key Vault Configuration
# -----------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'"
  }
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

  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days"
  }
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
