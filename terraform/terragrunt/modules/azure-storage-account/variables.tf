variable "storage_accounts" {
  description = "Map of storage accounts to create"
  type = map(object({
    name                            = string
    resource_group_name             = string
    location                        = string
    account_tier                    = string
    account_replication_type        = string
    account_kind                    = optional(string, "StorageV2")
    min_tls_version                 = optional(string, "TLS1_2")
    allow_nested_items_to_be_public = optional(bool, false)
    shared_access_key_enabled       = optional(bool, true)
    public_network_access_enabled   = optional(bool, true)
    tags                            = optional(map(string), {})

    # Optional RBAC assignments
    # Map of assignments: key => {principal_id, role}
    rbac_assignments = optional(map(object({
      principal_id = string
      role         = string # e.g., "Storage Blob Data Contributor"
    })), {})
  }))
  default = {}
}

variable "common_tags" {
  description = "Common tags to apply to all storage accounts"
  type        = map(string)
  default     = {}
}
