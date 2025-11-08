# Personal Subscription - React Web App + Function App
# Deploys: React SPA on App Service + FastAPI Function App backend
# Auth: None (public access)

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars        = include.root.locals
  preferred_region = get_env("PERSONAL_SUB_REGION", "uksouth")
}

inputs = {
  location     = local.preferred_region
  project_name = "subnetcalc"
  environment  = local.root_vars.environment

  # Use existing resource group
  resource_group_name   = "rg-subnet-calc"
  create_resource_group = false

  tenant_id = get_env("ARM_TENANT_ID", "")

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "subnet-calculator-react-webapp"
  }

  # web_app and function_app defined in terraform.tfvars
}
