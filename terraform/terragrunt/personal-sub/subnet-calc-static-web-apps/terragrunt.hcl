# Personal Subscription - Subnet Calculator Static Web Apps
# Manages existing Static Web Apps and their linked Function Apps
# Resources: 3x Static Web Apps, 3x Function Apps, App Service Plans, Storage Accounts

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../modules/azure-static-web-app"
}

locals {
  root_vars        = include.root.locals
  preferred_region = get_env("PERSONAL_SUB_REGION", "uksouth")
}

inputs = {
  location            = local.preferred_region
  resource_group_name = "rg-subnet-calc"
  project_name        = "subnetcalc"

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "subnet-calculator-static-web-apps"
  }

  # stacks defined in terraform.tfvars
}
