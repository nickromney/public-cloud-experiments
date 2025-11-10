variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "subnetcalc"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create a new resource group or use existing"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Observability Configuration
# -----------------------------------------------------------------------------

variable "observability" {
  description = "Observability configuration - can use existing or create new resources"
  type = object({
    use_existing                 = bool
    existing_resource_group_name = optional(string)
    existing_log_analytics_name  = optional(string)
    existing_app_insights_name   = optional(string)
    log_retention_days           = optional(number, 30)
    app_insights_retention_days  = optional(number, 90)
  })
  default = {
    use_existing = false
  }
}

# -----------------------------------------------------------------------------
# API Management Configuration
# -----------------------------------------------------------------------------

variable "apim" {
  description = "API Management configuration"
  type = object({
    name                  = optional(string, "")
    publisher_name        = string
    publisher_email       = string
    sku_name              = optional(string, "Developer_1") # Developer tier
    api_path              = optional(string, "subnet-calc")
    api_display_name      = optional(string, "Subnet Calculator API")
    subscription_required = optional(bool, true)
    rate_limit_per_minute = optional(number, 100)
  })

  validation {
    condition     = can(regex("^Developer_", var.apim.sku_name))
    error_message = "APIM SKU must be Developer tier (Developer_1)"
  }
}

# -----------------------------------------------------------------------------
# Function App Configuration
# -----------------------------------------------------------------------------

variable "function_app" {
  description = "Function App configuration (AUTH_METHOD=none, protected by APIM)"
  type = object({
    name                          = optional(string, "")
    plan_sku                      = optional(string, "EP1")
    runtime                       = optional(string, "python")
    runtime_version               = optional(string, "3.11")
    storage_account_name          = optional(string, "")
    public_network_access_enabled = optional(bool, true)
    cors_allowed_origins          = optional(list(string), [])
    app_settings                  = optional(map(string), {})
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "security" {
  description = "Security configuration for APIM-to-Function App communication"
  type = object({
    enforce_apim_only_access = bool
  })
  default = {
    enforce_apim_only_access = false
  }

  validation {
    condition     = can(var.security.enforce_apim_only_access)
    error_message = "enforce_apim_only_access must be explicitly set to true or false"
  }
}

# -----------------------------------------------------------------------------
# Web App Configuration
# -----------------------------------------------------------------------------

variable "web_app" {
  description = "Web App configuration (React SPA via APIM)"
  type = object({
    name            = optional(string, "")
    plan_sku        = optional(string, "B1")
    runtime_version = optional(string, "22-lts")
    api_base_url    = optional(string, "") # Auto-computed from APIM if empty
    always_on       = optional(bool, true)
    app_settings    = optional(map(string), {})
  })
  default = {}
}
