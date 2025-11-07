# Personal Subscription - Subnet Calculator with Internal APIM
# Deploys: Web App + Function App + Internal APIM + VNet + Azure AD

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars = include.root.locals

  # Cloudflare IP ranges for optional IP restrictions
  cloudflare_ips = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17"
  ]
}

inputs = {
  # Location and naming from root
  location     = local.root_vars.region
  project_name = local.root_vars.project_name
  environment  = local.root_vars.environment

  # Resource group
  resource_group_name   = "${local.root_vars.project_name}-${local.root_vars.environment}-rg"
  create_resource_group = true

  # Azure AD tenant
  tenant_id = get_env("ARM_TENANT_ID", "")

  # Tags
  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "subnet-calculator"
  }

  cloudflare_ips = local.cloudflare_ips

  # All other inputs come from terraform.tfvars
  # This allows easy configuration without editing terragrunt.hcl
}
