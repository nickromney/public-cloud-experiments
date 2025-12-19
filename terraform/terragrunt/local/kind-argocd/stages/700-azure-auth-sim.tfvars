# Stage 700 - Azure Auth Simulation
# Deploys Actions runner and Azure auth sim via Argo CD

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

cluster_name       = "kind-local"
kubeconfig_path    = "~/.kube/config"
kubeconfig_context = "kind-kind-local"
kind_config_path   = "./kind-config.yaml"

# -----------------------------------------------------------------------------
# Feature Toggles
# -----------------------------------------------------------------------------

enable_cilium                    = true
enable_cilium_mesh_auth          = true
enable_hubble                    = true
enable_namespaces                = true
enable_argocd                    = true
enable_gitea                     = true
enable_policies                  = true
enable_victoria_metrics          = false
enable_signoz                    = true
enable_signoz_k8s_infra          = true
enable_actions_runner            = true
enable_docker_socket_mount       = true
enable_azure_auth_sim            = true
enable_subnetcalc_azure_auth_sim = true
enable_azure_entraid_sim         = true
enable_azure_auth_ports          = true
enable_llm_sentiment             = true
use_external_gitea               = false

# Sidecar pattern: oauth2-proxy + frontend in same pod (4 pods instead of 5)
# See AZURE_AUTH_SIM.md for details.
azure_auth_sim_use_sidecar = false

# -----------------------------------------------------------------------------
# Versions / Ports
# -----------------------------------------------------------------------------

cilium_version                        = "1.18.4"
argocd_chart_version                  = "7.5.2"
argocd_namespace                      = "argocd"
argocd_server_node_port               = 30080
hubble_ui_node_port                   = 31235
gitea_chart_version                   = "12.4.0"
gitea_http_node_port                  = 30090
gitea_ssh_node_port                   = 30022
azure_auth_oauth2_proxy_host_port     = 3007
azure_auth_oauth2_proxy_host_port_uat = 3008
azure_auth_oauth2_proxy_node_port     = 30075
azure_auth_oauth2_proxy_node_port_uat = 30076
azure_auth_gateway_host_port          = 443
azure_auth_gateway_node_port          = 30070
azure_auth_apim_host_port             = 8082
azure_auth_apim_node_port             = 30082
azure_auth_api_host_port              = 8081
azure_auth_api_node_port              = 30081
azure_auth_keycloak_host_port         = 8180
azure_auth_keycloak_node_port         = 30180

# -----------------------------------------------------------------------------
# Gitea Addressing
# -----------------------------------------------------------------------------

gitea_ssh_username      = "git"
gitea_http_scheme       = "http"
gitea_http_host         = "127.0.0.1"
gitea_http_port         = 30090
gitea_ssh_host          = "127.0.0.1"
gitea_ssh_port          = 30022
gitea_http_host_local   = "127.0.0.1"
gitea_ssh_host_local    = "127.0.0.1"
gitea_ssh_host_cluster  = "gitea-ssh.gitea.svc.cluster.local"
gitea_ssh_port_cluster  = 22
gitea_http_host_cluster = "gitea-http.gitea.svc.cluster.local"
gitea_http_port_cluster = 3000
gitea_registry_host     = "localhost:30090"

# -----------------------------------------------------------------------------
# SSH Keys
# -----------------------------------------------------------------------------

generate_repo_ssh_key = true
ssh_private_key_path  = "./.run/argocd-repo.id_ed25519"
ssh_public_key_path   = "./.run/argocd-repo.id_ed25519.pub"

# -----------------------------------------------------------------------------
# Exposed Services (ports pre-configured, available after respective stages)
# -----------------------------------------------------------------------------
# - Argo CD UI: http://localhost:30080 (stage 400+)
# - Hubble UI: http://localhost:31235 (stage 300+)
# - Gitea UI: http://localhost:30090 (stage 500+)
# - Gitea SSH: ssh://localhost:30022 (stage 500+)
# - Azure auth sim (dev): http://localhost:3007 (stage 700)
# - Azure auth sim (uat): http://localhost:3008 (stage 700)
# - Azure auth gateway (NGINX Gateway Fabric): http://localhost:3007 (stage 700)
#   Keycloak/APIM/FastAPI remain internal—use kubectl port-forward if you need direct access.

# -----------------------------------------------------------------------------
# Namespaces
# -----------------------------------------------------------------------------
azure_auth_namespaces = {
  dev = "dev"
  uat = "uat"
}

azure_auth_gateway_namespace = "azure-auth-gateway"
