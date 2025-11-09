variable "project_name" {
  description = "Project short name used for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment identifier (dev, prod, etc.)."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID used for Easy Auth configuration."
  type        = string
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
      client_id                  = string
      client_secret              = optional(string, "")
      client_secret_setting_name = optional(string, "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET")
      issuer                     = optional(string, "")
      tenant_id                  = optional(string, "")
      allowed_audiences          = optional(list(string), [])
      runtime_version            = optional(string, "~1")
      unauthenticated_action     = optional(string, "RedirectToLoginPage")
      token_store_enabled        = optional(bool, true)
      login_parameters           = optional(map(string), {})
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
