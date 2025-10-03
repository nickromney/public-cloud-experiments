# Common configuration for spoke networking
# Based on Azure AKS baseline architecture

locals {
  # Each spoke gets a /16 network
  # Spoke A: 10.240.0.0/16
  # Spoke B: 10.241.0.0/16
  # etc.

  # Common subnet pattern for AKS workloads
  aks_subnets = {
    nodepools = {
      cidr = "0.0/22" # /22 = 1024 IPs (relative to spoke /16)
      # Example: 10.240.0.0/22 in spoke 10.240.0.0/16
    }
    internal_lb = {
      cidr = "4.0/28" # /28 = 16 IPs
      # Example: 10.240.4.0/28
    }
    private_endpoints = {
      cidr = "4.32/28" # /28 = 16 IPs
      # Example: 10.240.4.32/28
    }
    app_gateway = {
      cidr = "5.0/24" # /24 = 256 IPs
      # Example: 10.240.5.0/24
    }
  }

  # Common subnet pattern for App Service workloads
  app_service_subnets = {
    vnet_integration = {
      cidr = "0.0/23" # /23 = 512 IPs (for VNet integration)
    }
    private_endpoints = {
      cidr = "4.0/28" # /28 = 16 IPs
    }
  }
}

# This is a pattern file - include it in actual terragrunt.hcl files
