variable "name" {
  description = "Name of the Function App"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,60}$", var.name))
    error_message = "Function App name must be 2-60 characters, lowercase alphanumeric and hyphens only"
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the Function App"
  type        = string
}

variable "plan_name" {
  description = "Name of the App Service Plan (ignored if existing_service_plan_id is provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.plan_name == "" || can(regex("^[a-zA-Z0-9-]{1,40}$", var.plan_name))
    error_message = "Service plan name must be 1-40 characters, alphanumeric and hyphens only"
  }
}

variable "plan_sku" {
  description = "SKU for the App Service Plan (e.g., Y1, EP1, EP2, EP3) (ignored if existing_service_plan_id is provided)"
  type        = string
  default     = "Y1"

  validation {
    condition     = can(regex("^(Y1|EP[1-3]|B[1-3]|S[1-3]|P[1-3]v[2-3])$", var.plan_sku))
    error_message = "Plan SKU must be a valid Function App SKU (Y1, EP1-EP3, B1-B3, S1-S3, P1v2-P3v3)"
  }
}

variable "existing_service_plan_id" {
  description = "ID of existing App Service Plan to use (if provided, new plan won't be created)"
  type        = string
  default     = null
  nullable    = true
}

variable "runtime" {
  description = "Function App runtime (python, node, dotnet-isolated)"
  type        = string

  validation {
    condition     = contains(["python", "node", "dotnet-isolated"], var.runtime)
    error_message = "Runtime must be python, node, or dotnet-isolated"
  }
}

variable "runtime_version" {
  description = "Runtime version (e.g., 3.11 for Python, 18 for Node, 8.0 for .NET)"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name (if empty, auto-generated from function app name) (ignored if existing_storage_account_id is provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase alphanumeric only"
  }
}

variable "existing_storage_account_id" {
  description = "ID of existing Storage Account to use (if provided, new storage account won't be created)"
  type        = string
  default     = null
  nullable    = true
}

variable "public_network_access_enabled" {
  description = "Enable public network access to the Function App"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_support_credentials" {
  description = "Enable CORS credentials support"
  type        = bool
  default     = false
}

variable "app_settings" {
  description = "Application settings for the Function App"
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
    unauthenticated_action     = optional(string, "Return401")
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

variable "managed_identity" {
  description = "Managed identity configuration for Azure service authentication (App Insights, Storage). Set enabled=false for environments without Entra ID access (e.g., Pluralsight sandboxes)."
  type = object({
    enabled                    = optional(bool, true)
    type                       = optional(string, "SystemAssigned") # SystemAssigned, UserAssigned, or SystemAssigned, UserAssigned
    user_assigned_identity_ids = optional(list(string), [])
  })
  default = {
    enabled = true
    type    = "SystemAssigned"
  }

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type)
    error_message = "Identity type must be 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition = (
      var.managed_identity.type == "SystemAssigned" ||
      (contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity.type) && length(var.managed_identity.user_assigned_identity_ids) > 0)
    )
    error_message = "When identity type includes 'UserAssigned', user_assigned_identity_ids must be provided."
  }
}

variable "app_insights_id" {
  description = "Application Insights resource ID (required when managed_identity.enabled is true for RBAC role assignment)"
  type        = string
  default     = null
  nullable    = true
}

variable "app_insights_connection_string" {
  description = "Application Insights connection string (for app settings)"
  type        = string
  default     = null
  nullable    = true
}
