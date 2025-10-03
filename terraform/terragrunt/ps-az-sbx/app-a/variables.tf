# Variables for Pluralsight app module
# All resources use map pattern for 0 to n flexibility

variable "location" {
  description = "Azure region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "existing_resource_group_name" {
  description = "Name of the existing Pluralsight vended resource group"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Storage Accounts - map pattern (0 to n)
variable "storage_accounts" {
  description = "Map of storage accounts to create"
  type = map(object({
    account_tier     = optional(string, "Standard")
    replication_type = optional(string, "LRS")
    purpose          = optional(string, "general")
  }))
  default = {}
}

# App Service Plans - map pattern (0 to n)
variable "app_service_plans" {
  description = "Map of app service plans to create"
  type = map(object({
    os_type  = string
    sku_name = string
  }))
  default = {}
}

# Function Apps - map pattern (0 to n)
variable "function_apps" {
  description = "Map of function apps to create"
  type = map(object({
    app_service_plan_key = string
    storage_account_key  = string
    runtime              = string
    runtime_version      = string
    app_settings         = optional(map(string), {})
  }))
  default = {}
}

# Static Web Apps - map pattern (0 to n)
variable "static_web_apps" {
  description = "Map of static web apps to create"
  type = map(object({
    sku_tier = optional(string, "Free")
    sku_size = optional(string, "Free")
  }))
  default = {}
}

# APIM Instances - map pattern (0 to n)
variable "apim_instances" {
  description = "Map of APIM instances to create"
  type = map(object({
    sku_name        = string
    publisher_name  = string
    publisher_email = string
  }))
  default = {}
}

# APIM APIs - map pattern (0 to n)
variable "apim_apis" {
  description = "Map of APIs to create in APIM"
  type = map(object({
    apim_key         = string
    function_app_key = string
    path             = string
    display_name     = string
    protocols        = list(string)
  }))
  default = {}
}
