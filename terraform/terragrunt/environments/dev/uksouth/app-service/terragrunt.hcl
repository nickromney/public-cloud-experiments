# App Service Terragrunt configuration

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment  = local.environment_vars.locals.environment
  region       = local.region_vars.locals.region
  region_short = local.region_vars.locals.region_short
}

inputs = {
  client_name    = "experiments"
  environment    = local.environment
  stack          = "app-service"
  location       = local.region
  location_short = local.region_short
}
