# Pluralsight Azure Sandbox - App A
# Single deployment with toggleable resources via maps

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars = include.root.locals
}

inputs = {
  # Location and naming
  location     = local.root_vars.region
  project_name = local.root_vars.project_name
  environment  = local.root_vars.environment

  # Tags
  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    sandbox     = "ps-az-sbx"
  }

  # All other inputs come from terraform.tfvars
  # This allows easy toggling of resources without editing terragrunt.hcl
}
