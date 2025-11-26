# Stage 400 - Namespaces + Argo CD
# Adds Kubernetes namespaces and Argo CD on top of stage 300
# This provides the GitOps platform for subsequent deployments

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
kubeconfig_path  = "~/.kube/config"
kind_config_path = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 400 adds namespaces and Argo CD
# -----------------------------------------------------------------------------

enable_cilium     = true
enable_hubble     = true
enable_namespaces = true # NEW: Create all namespaces
enable_argocd     = true # NEW: Install Argo CD
enable_gitea      = false
enable_policies   = false

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

cilium_version          = "1.18.4"
argocd_chart_version    = "7.5.2"
argocd_namespace        = "argocd"
argocd_server_node_port = 30080
hubble_ui_node_port     = 31235 # Hubble UI enabled via Cilium config
gitea_chart_version     = "12.4.0"
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022

# -----------------------------------------------------------------------------
# SSH Keys for Argo CD repository access
# These variables define SSH keys for Argo CD to access private Git repositories.
# They are not required for namespace creation, and can be left unset unless
# you need Argo CD to access private repositories via SSH (used in stage 500).
# -----------------------------------------------------------------------------

generate_repo_ssh_key = true
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"

# -----------------------------------------------------------------------------
# Exposed Services
# -----------------------------------------------------------------------------
# - Argo CD UI: http://localhost:30080 (admin password via: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
# - Hubble UI: http://localhost:31235 (from stage 300)
# -----------------------------------------------------------------------------
