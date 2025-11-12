variable "identities" {
  description = "Map of user-assigned identities to create"
  type = map(object({
    name                = string
    resource_group_name = string
    location            = string
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all identities"
  type        = map(string)
  default     = {}
}
