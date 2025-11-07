include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/cloudflare-site"
}

# Pass account_id from environment variable
inputs = {
  account_id = get_env("CLOUDFLARE_ACCOUNT_ID", "")
}
