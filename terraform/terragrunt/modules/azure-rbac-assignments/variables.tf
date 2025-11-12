variable "role_assignments" {
  description = "Map of RBAC role assignments to create"
  type = map(object({
    scope                = string
    role_definition_name = string
    principal_id         = string
  }))
  default = {}
}
