# Stage 400 - Kind Cluster + Cilium + Namespaces + Argo CD
# Adds Argo CD on top of stage 300
# This is the target working stage with cluster, networking, and GitOps platform
# Hubble UI is included via Cilium configuration

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
worker_count     = 4
node_image       = "kindest/node:v1.29.2"
kind_config_path = "./kind-config.yaml"
kubeconfig_path  = "./.run/kubeconfig"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 400 adds Argo CD
# -----------------------------------------------------------------------------

enable_cilium     = true
enable_namespaces = true
enable_argocd     = true # NEW: Install Argo CD
enable_gitea      = false

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

cilium_version          = "1.18.4"
argocd_chart_version    = "7.5.2"
argocd_namespace        = "argocd"
argocd_server_node_port = 30080
hubble_ui_node_port     = 30007 # Hubble UI enabled via Cilium config
gitea_chart_version     = "12.4.0"
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022

# -----------------------------------------------------------------------------
# SSH Keys (not used in this stage, but required for argocd namespace creation)
# -----------------------------------------------------------------------------

generate_repo_ssh_key = true
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"

# -----------------------------------------------------------------------------
# Exposed Services
# -----------------------------------------------------------------------------
# - Argo CD UI: http://localhost:30080 (admin password via: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
# - Hubble UI: http://localhost:30007
# -----------------------------------------------------------------------------
