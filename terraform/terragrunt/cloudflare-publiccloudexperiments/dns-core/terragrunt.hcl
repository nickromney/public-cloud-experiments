include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/cloudflare-site"
}

inputs = {
  zone_name = "publiccloudexperiments.net"
  records   = {}
}
