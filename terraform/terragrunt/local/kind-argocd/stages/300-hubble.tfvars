# Stage 300 - Kind Cluster + Cilium + Hubble UI
# Adds Hubble UI on top of stage 200 (helm upgrade to enable Hubble)
# Provides network observability via Hubble UI at http://localhost:30007

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
worker_count     = 4
node_image       = "kindest/node:v1.29.2"
kind_config_path = "./kind-config.yaml"
kubeconfig_path  = "./.run/kubeconfig"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 300 adds Hubble UI
# -----------------------------------------------------------------------------

enable_cilium     = true
enable_hubble     = true # NEW: Enable Hubble UI (helm upgrade)
enable_namespaces = false
enable_argocd     = false
enable_gitea      = false
enable_policies   = false

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

# -----------------------------------------------------------------------------
# Exposed Services
# -----------------------------------------------------------------------------
# - Hubble UI: http://localhost:30007
# -----------------------------------------------------------------------------
