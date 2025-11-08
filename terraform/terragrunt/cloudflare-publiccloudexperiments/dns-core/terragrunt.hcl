include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/cloudflare-site"
}

# Records and zone_name are defined in terraform.tfvars
# Zone ID is also defined in terraform.tfvars
inputs = {}
