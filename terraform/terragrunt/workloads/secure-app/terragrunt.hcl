include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/secure-app"
}

locals {
  default_tags = {
    workload = "secure-app"
  }
}

inputs = {
  tags = local.default_tags
}
