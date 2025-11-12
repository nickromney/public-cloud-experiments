variable "service_plans" {
  description = "Map of service plans to create"
  type = map(object({
    name                = string
    resource_group_name = string
    location            = string
    os_type             = string
    sku_name            = string
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all service plans"
  type        = map(string)
  default     = {}
}
