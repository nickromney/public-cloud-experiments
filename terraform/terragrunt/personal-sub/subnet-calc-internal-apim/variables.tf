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
  description = "Azure region for resources."
  type        = string

  validation {
    condition     = contains(["uksouth", "ukwest", "eastus", "eastus2", "westeurope"], var.location)
    error_message = "Location must be one of: uksouth, ukwest, eastus, eastus2, westeurope"
  }
}

variable "tenant_id" {
  description = "Azure AD tenant ID used for managed identity token validation."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid UUID"
  }
}

variable "resource_group_name" {
  description = "Resource group name to deploy into."
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

variable "vnet_cidr" {
  description = "CIDR for the workload virtual network."
  type        = string
}

variable "subnets" {
  description = "Subnet CIDRs used within the VNet."
  type = object({
    web_integration_cidr   = string
    private_endpoints_cidr = string
    apim_cidr              = string
  })
}

variable "cloudflare_ips" {
  description = "List of Cloudflare egress IP ranges allowed to reach the web app."
  type        = list(string)
  default     = []
}

variable "web_app" {
  description = "Configuration for the public facing App Service."
  type = object({
    name                    = optional(string, "")
    plan_sku                = string
    runtime_version         = optional(string, "18-lts")
    api_base_url            = string
    always_on               = optional(bool, true)
    cloudflare_only         = optional(bool, false)
    enable_private_endpoint = optional(bool, false)
    app_settings            = optional(map(string), {})
  })
}

variable "function_app" {
  description = "Configuration for the backend Function App."
  type = object({
    name                    = optional(string, "")
    plan_sku                = string
    runtime                 = string
    runtime_version         = string
    run_from_package        = optional(bool, true)
    app_settings            = optional(map(string), {})
    storage_account_name    = optional(string, "")
    enable_private_endpoint = optional(bool, true)
  })
}

variable "apim" {
  description = "Configuration for API Management."
  type = object({
    name            = optional(string, "")
    sku_name        = string
    publisher_name  = string
    publisher_email = string
    api_path        = string
    policy_xml      = optional(string, null)
    identifier_uri  = optional(string, "")
  })
}
