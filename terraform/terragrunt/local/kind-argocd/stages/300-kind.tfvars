# Stage 100 - Kind Cluster Bootstrap (Terraform-driven)
# Replaces `make local kind create`; uses the kind provider to create the cluster
# with NodePort mappings for Argo CD, Gitea, Hubble, and azure auth simulation ports.

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name       = "kind-local"
kubeconfig_path    = "~/.kube/config"
kubeconfig_context = "" # use current context to avoid validation before kind exists
kind_config_path   = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles - Stage 100 creates only the cluster (no addons)
# -----------------------------------------------------------------------------

enable_cilium           = false
enable_hubble           = false
enable_namespaces       = false
enable_argocd           = false
enable_gitea            = false
enable_policies         = false
enable_azure_auth_sim   = false # just cluster; app will be enabled in later stages
enable_azure_auth_ports = true

# -----------------------------------------------------------------------------
# Versions / Ports (kept for consistency across stages)
# -----------------------------------------------------------------------------

cilium_version                    = "1.18.4"
argocd_chart_version              = "7.5.2"
argocd_namespace                  = "argocd"
argocd_server_node_port           = 30080
hubble_ui_node_port               = 31235
gitea_chart_version               = "12.4.0"
gitea_http_node_port              = 30090
gitea_ssh_node_port               = 30022
azure_auth_oauth2_proxy_host_port = 3007
azure_auth_oauth2_proxy_node_port = 30070
azure_auth_apim_host_port         = 8082
azure_auth_apim_node_port         = 30082
azure_auth_api_host_port          = 8081
azure_auth_api_node_port          = 30081
azure_auth_keycloak_host_port     = 8180
azure_auth_keycloak_node_port     = 30180

# -----------------------------------------------------------------------------
# SSH Keys (placeholders to satisfy variable definitions)
# -----------------------------------------------------------------------------

generate_repo_ssh_key = false
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"
