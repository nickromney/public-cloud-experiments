variable "name" {
  description = "Name of the Web App"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,60}$", var.name))
    error_message = "Web App name must be 2-60 characters, lowercase alphanumeric and hyphens only"
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the Web App"
  type        = string
}

variable "plan_name" {
  description = "Name of the App Service Plan"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,40}$", var.plan_name))
    error_message = "Service plan name must be 1-40 characters, alphanumeric and hyphens only"
  }
}

variable "plan_sku" {
  description = "SKU for the App Service Plan (e.g., B1, S1, P1v3)"
  type        = string

  validation {
    condition     = can(regex("^(B[1-3]|S[1-3]|P[1-3]v[2-3]|F1|D1)$", var.plan_sku))
    error_message = "Plan SKU must be a valid App Service SKU (B1-B3, S1-S3, P1v2-P3v3, F1, D1)"
  }
}

variable "runtime_version" {
  description = "Node.js runtime version (e.g., 18-lts, 20-lts, 22-lts)"
  type        = string
  default     = "20-lts"

  validation {
    condition     = can(regex("^(16|18|20|22)-lts$", var.runtime_version))
    error_message = "Runtime version must be a supported Node.js LTS version (16-lts, 18-lts, 20-lts, 22-lts)"
  }
}

variable "always_on" {
  description = "Keep the app loaded even when there's no traffic"
  type        = bool
  default     = true
}

variable "default_documents" {
  description = "Default documents for the Web App"
  type        = list(string)
  default     = ["index.html"]
}

variable "app_settings" {
  description = "Application settings for the Web App"
  type        = map(string)
  default     = {}
}

variable "tenant_id" {
  description = "Azure AD tenant ID for Easy Auth (defaults to current context if not specified)"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid UUID"
  }
}

variable "easy_auth" {
  description = "Easy Auth V2 configuration with managed identity support"
  type = object({
    enabled                    = optional(bool, true)
    client_id                  = string
    client_secret_setting_name = optional(string, "")
    issuer                     = optional(string, "")
    tenant_id                  = optional(string, "")
    allowed_audiences          = optional(list(string), [])
    runtime_version            = optional(string, "~1")
    unauthenticated_action     = optional(string, "RedirectToLoginPage")
    token_store_enabled        = optional(bool, true)
    login_parameters           = optional(map(string), {})
    use_managed_identity       = optional(bool, true)
  })
  default  = null
  nullable = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
