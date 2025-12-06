# Stage 950 - In-cluster Gitea with Actions Runner
# Full self-contained deployment: Gitea, runner, and azure-auth-sim all in Kubernetes
# No external services required - everything runs in the Kind cluster

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name     = "kind-local"
kubeconfig_path  = "~/.kube/config"
kind_config_path = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles - Everything enabled with in-cluster Gitea
# -----------------------------------------------------------------------------

enable_cilium           = true
enable_hubble           = true
enable_namespaces       = true
enable_argocd           = true
enable_gitea            = true
enable_policies         = true
enable_actions_runner   = true
enable_azure_auth_sim   = true
enable_azure_auth_ports = true

# KEY DIFFERENCE: Use in-cluster Gitea instead of external
use_external_gitea = false

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

cilium_version          = "1.18.4"
argocd_chart_version    = "7.5.2"
argocd_namespace        = "argocd"
argocd_server_node_port = 30080
hubble_ui_node_port     = 31235

# In-cluster Gitea Helm chart
gitea_chart_version  = "12.4.0"
gitea_ssh_username   = "git"

# -----------------------------------------------------------------------------
# Gitea Addressing - ALL host/port configurations in one place
# -----------------------------------------------------------------------------

# NodePorts exposed on Kind cluster (accessible from host via 127.0.0.1:port)
gitea_http_node_port = 30090
gitea_ssh_node_port  = 30022

# Local access (Terraform provisioners running on host machine)
gitea_http_host_local = "127.0.0.1"
gitea_ssh_host_local  = "127.0.0.1"
gitea_http_scheme     = "http"  # In-cluster uses HTTP
gitea_http_host       = "127.0.0.1"  # Used by some provisioners for local curl
gitea_http_port       = 30090        # NodePort when accessing locally
gitea_ssh_host        = "127.0.0.1"  # Used by git remote add (local)
gitea_ssh_port        = 30022        # NodePort when accessing locally

# Cluster-internal access (ArgoCD, kubectl run, pods inside Kubernetes)
gitea_ssh_host_cluster  = "gitea-ssh.gitea.svc.cluster.local"
gitea_ssh_port_cluster  = 22
gitea_http_host_cluster = "gitea-http.gitea.svc.cluster.local"
gitea_http_port_cluster = 3000

# Container registry for image pulls by containerd on Kind nodes
# Must use localhost:NodePort because containerd runs on nodes (not in pods)
# and cannot resolve Kubernetes DNS names like gitea-http.gitea.svc.cluster.local
# This address is used for:
# - Deployment YAML image references (pods pulling images)
# - Containerd insecure registry config (allows HTTP instead of HTTPS)
# - REGISTRY_HOST secret for Docker login/push from workflow
gitea_registry_host = "localhost:30090"

# Docker socket path on host (mounted into Kind nodes for runner)
docker_socket_path = "/var/run/docker.sock"

# -----------------------------------------------------------------------------
# SSH Keys (required for Gitea repo access)
# -----------------------------------------------------------------------------

generate_repo_ssh_key = true
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"

# -----------------------------------------------------------------------------
# Notes
# -----------------------------------------------------------------------------
# - ArgoCD UI: http://localhost:30080
# - Gitea UI: http://localhost:30090
# - Azure auth sim entry (OAuth2 Proxy / frontend): http://localhost:3007
# - Keycloak: http://localhost:8180
# - APIM simulator: http://localhost:8082
# - FastAPI backend: http://localhost:8081
#
# Deployment Flow:
# 1. terragrunt apply (creates Kind cluster, deploys Gitea via ArgoCD)
# 2. Terraform creates repos, seeds them, registers runner
# 3. Runner builds images and pushes to in-cluster Gitea registry
# 4. ArgoCD deploys azure-auth-sim using in-cluster registry images
