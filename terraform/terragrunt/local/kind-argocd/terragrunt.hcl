# Local context: kind cluster + ArgoCD + Cilium/Hubble on Podman

include "root" {
  path   = find_in_parent_folders("root-local.hcl")
  expose = true
}

locals {
  root_vars = include.root.locals
}

inputs = {
  cluster_name          = "kind-local"
  worker_count          = 4
  node_image            = "kindest/node:v1.29.2"
  kind_config_path      = "${get_terragrunt_dir()}/kind-config.yaml"
  kubeconfig_path       = "${get_terragrunt_dir()}/.run/kubeconfig"
  cilium_version        = "1.18.4"
  argocd_chart_version  = "7.5.2"
  argocd_namespace      = "argocd"
  argocd_server_node_port = 30080
  hubble_ui_node_port   = 30007
  gitea_chart_version   = "12.4.0"
  generate_repo_ssh_key = true
  ssh_private_key_path  = "${get_terragrunt_dir()}/.run/argocd-repo.id_ed25519"
  ssh_public_key_path   = "${get_terragrunt_dir()}/.run/argocd-repo.id_ed25519.pub"
}
