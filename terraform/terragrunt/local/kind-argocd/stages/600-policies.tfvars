# Stage 600 - Complete Stack with Policies
# Adds Cilium and Kyverno policies on top of stage 500
# Policies are deployed via Argo CD from the Gitea repository
# This is the complete working stack

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
kubeconfig_path  = "~/.kube/config"
kind_config_path = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 600 adds all policies
# -----------------------------------------------------------------------------

enable_cilium     = true
enable_hubble     = true
enable_namespaces = true
enable_argocd     = true
enable_gitea      = true
enable_policies   = true # NEW: Deploy Cilium policies, Kyverno, and Kyverno policies
enable_azure_auth_sim = true
enable_azure_auth_ports = true

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

cilium_version          = "1.18.4"
argocd_chart_version    = "7.5.2"
argocd_namespace        = "argocd"
argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
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
# - Hubble UI: http://localhost:31235
# - Gitea UI: http://localhost:30090 (gitea-admin / ChangeMe123!)
# - Gitea SSH: ssh://localhost:30022
#
# Deployed Applications (via Argo CD):
# - Gitea (Git repository)
# - Cilium Network Policies (from Gitea repo)
# - Kyverno (Policy engine)
# - Kyverno Policies (from Gitea repo)
# -----------------------------------------------------------------------------
