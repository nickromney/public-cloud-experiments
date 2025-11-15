# Hub networking configuration
# Creates the central hub VNet (10.200.0.0/24) with Firewall, Gateway, and Bastion subnets

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "hub_common" {
  path = "${get_repo_root()}/terraform/terragrunt/_envcommon/hub-networking.hcl"
}

locals {
  root_vars = include.root.locals
  hub_vars  = include.hub_common.locals
}

terraform {
  source = "${get_repo_root()}/terraform/modules/hub-networking"
}

inputs = {
  # Location
  location = local.root_vars.region

  # Naming
  resource_group_name = "rg-${local.root_vars.project_name}-${local.root_vars.environment}-hub-network"
  vnet_name           = "vnet-${local.root_vars.project_name}-${local.root_vars.environment}-hub"

  # Network configuration from common pattern
  vnet_address_space = [local.hub_vars.hub_vnet_cidr]
  subnets            = local.hub_vars.subnets

  # Tags
  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    component   = "networking"
    tier        = "shared"
  }
}
