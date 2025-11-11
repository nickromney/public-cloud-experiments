variable "name" {
  description = "Name of the user-assigned managed identity"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{3,128}$", var.name))
    error_message = "Identity name must be 3-128 characters, alphanumeric, underscores, and hyphens only"
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the identity"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the identity"
  type        = map(string)
  default     = {}
}
