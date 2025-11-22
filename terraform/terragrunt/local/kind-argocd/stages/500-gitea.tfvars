# Stage 500 - Kind Cluster + Cilium + Hubble + Namespaces + Argo CD + Gitea
# Adds Gitea on top of stage 400
# Gitea is deployed via Argo CD and hosts the policy repository

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
worker_count     = 4
node_image       = "kindest/node:v1.29.2"
kind_config_path = "./kind-config.yaml"
kubeconfig_path  = "./.run/kubeconfig"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 500 adds Gitea
# -----------------------------------------------------------------------------

enable_cilium     = true
enable_hubble     = true
enable_namespaces = true
enable_argocd     = true
enable_gitea      = true # NEW: Install Gitea via Argo CD
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
# SSH Keys (required for Gitea repo access)
# -----------------------------------------------------------------------------

generate_repo_ssh_key = true
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"

# -----------------------------------------------------------------------------
# Exposed Services
# -----------------------------------------------------------------------------
# - Argo CD UI: http://localhost:30080 (admin password via: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
# - Hubble UI: http://localhost:30007
# - Gitea UI: http://localhost:30090 (gitea-admin / ChangeMe123!)
# - Gitea SSH: ssh://localhost:30022
# -----------------------------------------------------------------------------
