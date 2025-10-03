# Common variables
variable "azure_region" {
  description = "Azure region to use"
  type        = string
}

variable "organisation" {
  description = "Organisation name (e.g., charity)"
  type        = string
}

variable "workload" {
  description = "Workload name (e.g., dataservices)"
  type        = string
}

variable "environment" {
  description = "Environment name (shared, dev, test, prod)"
  type        = string

  validation {
    condition     = contains(["shared", "dev", "test", "uat", "prod"], var.environment)
    error_message = "Environment must be one of: shared, dev, test, uat, prod"
  }
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "shared_environment_suffix" {
  description = "Suffix for shared resources (e.g., 'nonprod', 'prod')"
  type        = string
  default     = "nonprod"
}

# Resource Group variables
variable "create_resource_group" {
  description = "Whether to create the resource group (only for shared environment)"
  type        = bool
  default     = true
}

variable "create_managed_identity" {
  description = "Whether to create a managed identity for the Service Bus namespace"
  type        = bool
  default     = true
}

variable "managed_identity_name" {
  description = "Custom name for the managed identity (if not provided, will be auto-generated)"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Override the resource group name (if not set, will use naming convention)"
  type        = string
  default     = ""
}

variable "existing_resource_group_name" {
  description = "Name of existing resource group (for non-shared environments)"
  type        = string
  default     = ""
}

# For shared environment - namespace configuration
variable "namespace_custom_name" {
  description = "Custom name for the Service Bus namespace (overrides naming convention)"
  type        = string
  default     = null
}

variable "servicebus_namespace_sku" {
  description = "SKU of the Service Bus namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.servicebus_namespace_sku)
    error_message = "Service Bus namespace SKU must be one of: Basic, Standard, Premium"
  }
}

variable "servicebus_namespace_capacity" {
  description = "The capacity of the Service Bus namespace (only for Premium SKU)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 2, 4, 8, 16], var.servicebus_namespace_capacity)
    error_message = "Service Bus namespace capacity must be one of: 0, 1, 2, 4, 8, 16"
  }
}

variable "zone_redundant" {
  description = "Enable zone redundancy (only for Premium SKU)"
  type        = bool
  default     = false
}

variable "local_auth_enabled" {
  description = "Whether to enable local authentication (connection strings)"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for the Service Bus namespace"
  type        = string
  default     = "1.2"
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access"
  type        = bool
  default     = true
}

variable "trusted_services_allowed" {
  description = "Whether to allow trusted Microsoft services to bypass firewall"
  type        = bool
  default     = true
}

# For non-shared environments - reference to existing namespace
variable "existing_namespace_name" {
  description = "Name of existing Service Bus namespace (for non-shared environments)"
  type        = string
  default     = ""
}

variable "existing_namespace_resource_group" {
  description = "Resource group of existing Service Bus namespace (for non-shared environments)"
  type        = string
  default     = ""
}

# Topics configuration (using Claranet module structure)
variable "servicebus_topics" {
  description = "List of Service Bus topics to create"
  type = list(object({
    name        = string
    custom_name = optional(string)

    status = optional(string, "Active")

    auto_delete_on_idle                     = optional(string)
    default_message_ttl                     = optional(string)
    duplicate_detection_history_time_window = optional(string)
    max_message_size_in_kilobytes           = optional(number)
    max_size_in_megabytes                   = optional(number)

    batched_operations_enabled   = optional(bool)
    partitioning_enabled         = optional(bool)
    express_enabled              = optional(bool)
    requires_duplicate_detection = optional(bool)
    support_ordering             = optional(bool)

    authorizations_custom_name = optional(string)
    authorizations = optional(object({
      listen = optional(bool, true)
      send   = optional(bool, true)
      manage = optional(bool, true)
    }), {})

    subscriptions = optional(list(object({
      name        = string
      custom_name = optional(string)

      status = optional(string, "Active")

      auto_delete_on_idle = optional(string)
      default_message_ttl = optional(string)
      lock_duration       = optional(string)
      max_delivery_count  = number

      batched_operations_enabled                = optional(bool, true)
      dead_lettering_on_message_expiration      = optional(bool)
      dead_lettering_on_filter_evaluation_error = optional(bool)
      requires_session                          = optional(bool)

      forward_to                        = optional(string)
      forward_dead_lettered_messages_to = optional(string)

      authorizations_custom_name = optional(string)
      authorizations = optional(object({
        listen = optional(bool, true)
        send   = optional(bool, true)
        manage = optional(bool, false)
      }), {})

      rules = optional(list(object({
        name           = string
        filter_type    = string # "SqlFilter" or "CorrelationFilter"
        sql_expression = optional(string)
        sql_action     = optional(string)
        correlation_filter = optional(object({
          correlation_id      = optional(string)
          message_id          = optional(string)
          to                  = optional(string)
          reply_to            = optional(string)
          label               = optional(string)
          session_id          = optional(string)
          reply_to_session_id = optional(string)
          content_type        = optional(string)
          properties          = optional(map(string), {})
        }))
      })), [])
    })), [])
  }))
  default = []
}

# Queues configuration (using Claranet module structure)
variable "servicebus_queues" {
  description = "List of Service Bus queues to create"
  type = list(object({
    name        = string
    custom_name = optional(string)

    status = optional(string, "Active")

    auto_delete_on_idle                     = optional(string)
    default_message_ttl                     = optional(string)
    duplicate_detection_history_time_window = optional(string)
    max_message_size_in_kilobytes           = optional(number)
    max_size_in_megabytes                   = optional(number)
    max_delivery_count                      = number
    lock_duration                           = optional(string)

    batched_operations_enabled           = optional(bool)
    partitioning_enabled                 = optional(bool)
    express_enabled                      = optional(bool)
    requires_duplicate_detection         = optional(bool)
    requires_session                     = optional(bool)
    dead_lettering_on_message_expiration = optional(bool)

    forward_to                        = optional(string)
    forward_dead_lettered_messages_to = optional(string)

    authorizations_custom_name = optional(string)
    authorizations = optional(object({
      listen = optional(bool, true)
      send   = optional(bool, true)
      manage = optional(bool, true)
    }), {})
  }))
  default = []
}

# Diagnostic settings
variable "logs_destinations_ids" {
  description = "List of destination resources IDs for logs diagnostic destination"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Base tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
