# Stage 200 - Cilium CNI
# Installs Cilium CNI on the existing kind cluster (created by `make local kind create`)
# This enables networking in the cluster

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
kubeconfig_path  = "~/.kube/config"
kind_config_path = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 200 adds Cilium CNI only
# -----------------------------------------------------------------------------

enable_cilium     = true  # NEW: Cilium CNI (networking only)
enable_hubble     = false # Hubble UI not yet enabled
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
# SSH Keys (required by variable definition, not used until stage 500)
# Placeholder values provided to satisfy variable requirements.
# -----------------------------------------------------------------------------

generate_repo_ssh_key = false
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"
