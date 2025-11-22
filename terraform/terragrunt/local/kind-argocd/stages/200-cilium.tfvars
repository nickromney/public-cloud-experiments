# Stage 200 - Kind Cluster + Cilium CNI
# Adds Cilium CNI with Hubble on top of stage 100
# This enables networking in the cluster and provides observability via Hubble UI

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
worker_count     = 4
node_image       = "kindest/node:v1.29.2"
kind_config_path = "./kind-config.yaml"
kubeconfig_path  = "./.run/kubeconfig"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 200 adds Cilium
# -----------------------------------------------------------------------------

enable_cilium     = true # NEW: Cilium CNI with Hubble enabled
enable_namespaces = false
enable_argocd     = false
enable_gitea      = false

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

cilium_version          = "1.18.4"
argocd_chart_version    = "7.5.2"
argocd_namespace        = "argocd"
argocd_server_node_port = 30080
hubble_ui_node_port     = 30007
gitea_chart_version     = "12.4.0"
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022

# -----------------------------------------------------------------------------
# SSH Keys (not used in this stage)
# -----------------------------------------------------------------------------

generate_repo_ssh_key = false
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"
