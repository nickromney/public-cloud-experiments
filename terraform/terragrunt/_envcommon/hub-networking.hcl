# Common configuration for hub networking
# Based on Azure AKS baseline architecture

locals {
  # Hub network configuration (10.200.0.0/24)
  hub_vnet_cidr = "10.200.0.0/24"

  # Subnets within hub
  subnets = {
    firewall = {
      name   = "AzureFirewallSubnet" # Must be exact name
      cidr   = "10.200.0.0/26"       # /26 = 64 IPs
      routes = []
    }
    gateway = {
      name   = "GatewaySubnet" # Must be exact name
      cidr   = "10.200.0.64/27" # /27 = 32 IPs
      routes = []
    }
    bastion = {
      name   = "AzureBastionSubnet" # Must be exact name
      cidr   = "10.200.0.128/26"    # /26 = 64 IPs
      routes = []
    }
  }
}

# This is a pattern file - include it in actual terragrunt.hcl files
# Then reference local.hub_vnet_cidr and local.subnets
