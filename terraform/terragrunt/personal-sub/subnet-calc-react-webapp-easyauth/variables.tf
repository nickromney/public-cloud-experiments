variable "project_name" {
  description = "Project short name used for resource naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters, lowercase alphanumeric and hyphens only"
  }
}

variable "environment" {
  description = "Environment identifier (dev, prod, etc.)."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "pre", "np", "qa", "uat"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod, pre, np, qa, uat"
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string

  validation {
    condition     = contains(["uksouth", "ukwest", "eastus", "eastus2", "westeurope"], var.location)
    error_message = "Location must be one of: uksouth, ukwest, eastus, eastus2, westeurope"
  }
}

variable "tenant_id" {
  description = "Azure AD tenant ID used for Easy Auth configuration (defaults to current Azure CLI context if not specified)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid UUID"
  }
}

variable "resource_group_name" {
  description = "Resource group name that hosts the stack."
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create the resource group (true) or assume it already exists (false)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}

variable "entra_id_app" {
  description = "Entra ID App Registration configuration for Easy Auth (client_id generated automatically)"
  type = object({
    display_name     = string
    sign_in_audience = optional(string, "AzureADMyOrg")
    identifier_uris  = optional(list(string), [])
  })
}

variable "web_app" {
  description = "Configuration for the React frontend hosted on App Service."
  type = object({
    name            = optional(string, "")
    plan_sku        = string
    runtime_version = optional(string, "20-lts")
    api_base_url    = optional(string, "")
    always_on       = optional(bool, true)
    app_settings    = optional(map(string), {})
    easy_auth = optional(object({
      enabled                    = optional(bool, true)
      client_id                  = optional(string, "") # Dynamically generated from Entra ID app
      client_secret_setting_name = optional(string, "")
      issuer                     = optional(string, "")
      tenant_id                  = optional(string, "")
      allowed_audiences          = optional(list(string), [])
      runtime_version            = optional(string, "~1")
      unauthenticated_action     = optional(string, "RedirectToLoginPage")
      token_store_enabled        = optional(bool, true)
      login_parameters           = optional(map(string), {})
      use_managed_identity       = optional(bool, true)
    }), null)
  })
}

variable "function_app" {
  description = "Configuration for the FastAPI Azure Function backend."
  type = object({
    name                          = optional(string, "")
    plan_sku                      = string
    runtime                       = string
    runtime_version               = string
    run_from_package              = optional(bool, true)
    storage_account_name          = optional(string, "")
    public_network_access_enabled = optional(bool, true)
    cors_allowed_origins          = optional(list(string), ["*"])
    app_settings                  = optional(map(string), {})
  })
}

variable "observability" {
  description = "Observability configuration for Application Insights and Log Analytics."
  type = object({
    log_retention_days          = optional(number, 30)
    app_insights_retention_days = optional(number, 90)
  })
  default = {
    log_retention_days          = 30
    app_insights_retention_days = 90
  }
}
