# Local Terragrunt root for on-device experiments (kind on Podman + OpenTofu)

terraform {
  # Ensure the kind provider uses Podman without extra shell exports
  extra_arguments "kind_podman_provider" {
    commands = ["init", "plan", "apply", "destroy"]
    env_vars = {
      KIND_EXPERIMENTAL_PROVIDER = "podman"
    }
  }
}

# Keep state in-repo under .run/ to avoid Azure backend requirements
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    path = "${get_parent_terragrunt_dir()}/.run/${path_relative_to_include()}/terraform.tfstate"
  }
}

locals {
  environment = "local"
}

# Use OpenTofu by default for this context
terraform_binary = "tofu"
