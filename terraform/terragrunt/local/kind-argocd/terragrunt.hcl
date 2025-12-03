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
  kubeconfig_path       = pathexpand("~/.kube/config")
  kubeconfig_context    = ""
  cilium_version        = "1.18.4"
  argocd_chart_version  = "7.5.2"
  argocd_namespace      = "argocd"
  argocd_server_node_port = 30080
  hubble_ui_node_port   = 31235
  gitea_chart_version   = "12.4.0"
  use_external_gitea    = true
  gitea_http_scheme     = "https"
  gitea_http_host       = "host.containers.internal"
  gitea_http_port       = 3000
  gitea_ssh_host        = "host.containers.internal"
  gitea_ssh_port        = 30022
  gitea_registry_host   = "host.containers.internal:3000"
  gitea_http_host_local = "127.0.0.1"
  gitea_ssh_host_local  = "127.0.0.1"
  gitea_ssh_username    = "gitea-admin"
  generate_repo_ssh_key = true
  ssh_private_key_path  = "${get_terragrunt_dir()}/.run/argocd-repo.id_ed25519"
  ssh_public_key_path   = "${get_terragrunt_dir()}/.run/argocd-repo.id_ed25519.pub"
  enable_actions_runner        = false
  enable_azure_auth_sim        = false
  enable_azure_auth_ports      = false
  azure_auth_namespace         = "azure-auth-sim"
  azure_auth_oauth2_proxy_host_port = 3007
  azure_auth_oauth2_proxy_node_port = 30070
  azure_auth_apim_host_port         = 8082
  azure_auth_apim_node_port         = 30082
  azure_auth_api_host_port          = 8081
  azure_auth_api_node_port          = 30081
  azure_auth_keycloak_host_port     = 8180
  azure_auth_keycloak_node_port     = 30180
}
