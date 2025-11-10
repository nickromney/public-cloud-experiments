# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "name" {
  description = "Name of the API Management instance"
  type        = string
}

variable "location" {
  description = "Azure region for the API Management instance"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "publisher_name" {
  description = "Publisher name for APIM"
  type        = string
}

variable "publisher_email" {
  description = "Publisher email for APIM"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.publisher_email))
    error_message = "Publisher email must be a valid email address"
  }
}

variable "sku_name" {
  description = "SKU of the API Management instance (e.g., Developer_1, Basic_1, Standard_1)"
  type        = string
  default     = "Developer_1"

  validation {
    condition     = can(regex("^(Developer|Basic|Standard|Premium)_[0-9]+$", var.sku_name))
    error_message = "SKU must be in format: tier_capacity (e.g., Developer_1, Basic_1)"
  }
}

# -----------------------------------------------------------------------------
# Networking Variables
# -----------------------------------------------------------------------------

variable "virtual_network_type" {
  description = "Virtual network type: None (public), Internal (private), or External (hybrid)"
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "Internal", "External"], var.virtual_network_type)
    error_message = "Virtual network type must be None, Internal, or External"
  }
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (required when virtual_network_type != None)"
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Observability Variables
# -----------------------------------------------------------------------------

variable "app_insights_id" {
  description = "Application Insights resource ID (optional, for diagnostics)"
  type        = string
  default     = null
}

variable "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (required if app_insights_id is set)"
  type        = string
  default     = null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Diagnostics Configuration
# -----------------------------------------------------------------------------

variable "diagnostics_sampling_percentage" {
  description = "Sampling percentage for diagnostics (0-100)"
  type        = number
  default     = 100.0

  validation {
    condition     = var.diagnostics_sampling_percentage >= 0 && var.diagnostics_sampling_percentage <= 100
    error_message = "Sampling percentage must be between 0 and 100"
  }
}

variable "diagnostics_always_log_errors" {
  description = "Whether to always log errors"
  type        = bool
  default     = true
}

variable "diagnostics_log_client_ip" {
  description = "Whether to log client IP addresses"
  type        = bool
  default     = true
}

variable "diagnostics_verbosity" {
  description = "Verbosity level for diagnostics (error, information, verbose)"
  type        = string
  default     = "information"

  validation {
    condition     = contains(["error", "information", "verbose"], var.diagnostics_verbosity)
    error_message = "Verbosity must be error, information, or verbose"
  }
}

variable "diagnostics_http_correlation_protocol" {
  description = "HTTP correlation protocol (None, Legacy, W3C)"
  type        = string
  default     = "W3C"

  validation {
    condition     = contains(["None", "Legacy", "W3C"], var.diagnostics_http_correlation_protocol)
    error_message = "HTTP correlation protocol must be None, Legacy, or W3C"
  }
}

variable "diagnostics_frontend_request_body_bytes" {
  description = "Number of request body bytes to log (frontend)"
  type        = number
  default     = 1024
}

variable "diagnostics_frontend_request_headers" {
  description = "Headers to log from frontend requests"
  type        = list(string)
  default = [
    "Ocp-Apim-Subscription-Key",
    "User-Agent"
  ]
}

variable "diagnostics_frontend_response_body_bytes" {
  description = "Number of response body bytes to log (frontend)"
  type        = number
  default     = 1024
}

variable "diagnostics_frontend_response_headers" {
  description = "Headers to log from frontend responses"
  type        = list(string)
  default = [
    "Content-Type"
  ]
}

variable "diagnostics_backend_request_body_bytes" {
  description = "Number of request body bytes to log (backend)"
  type        = number
  default     = 1024
}

variable "diagnostics_backend_request_headers" {
  description = "Headers to log from backend requests"
  type        = list(string)
  default = [
    "X-User-ID",
    "X-User-Name"
  ]
}

variable "diagnostics_backend_response_body_bytes" {
  description = "Number of response body bytes to log (backend)"
  type        = number
  default     = 1024
}

variable "diagnostics_backend_response_headers" {
  description = "Headers to log from backend responses"
  type        = list(string)
  default = [
    "Content-Type"
  ]
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
