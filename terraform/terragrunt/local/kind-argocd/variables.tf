variable "cluster_name" {
  description = "Name for the kind cluster."
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes to create (control plane is added automatically)."
  type        = number
  default     = 4
}

variable "node_image" {
  description = "Kind node image."
  type        = string
  default     = "kindest/node:v1.35.0"
}

variable "kind_api_server_port" {
  description = "Host port to bind the Kubernetes API server to (prevents kind from choosing a random port that may already be in use)."
  type        = number
  default     = 6443
}

variable "dockerhub_username" {
  description = "Optional Docker Hub username for kind node containerd pulls (helps avoid anonymous pull rate limits)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "dockerhub_password" {
  description = "Optional Docker Hub password/token for kind node containerd pulls (helps avoid anonymous pull rate limits)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "kind_config_path" {
  description = "Path to write the rendered kind cluster config."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to write the kubeconfig for the cluster."
  type        = string
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use for Kubernetes/Helm providers (empty string to use current context)."
  type        = string
  default     = ""
}

variable "cilium_version" {
  description = "Cilium Helm chart version to install."
  type        = string
  default     = "1.18.5"
}

variable "cilium_enable_wireguard" {
  description = "Enable Cilium WireGuard node-to-node encryption (can be unstable on kind; defaults off)."
  type        = bool
  default     = false
}

variable "enable_cilium_mesh_auth" {
  description = "Enable Cilium mesh-auth (SPIRE-based mutual authentication). Disabled by default for local kind stability."
  type        = bool
  default     = false
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version to install."
  type        = string
  default     = "9.1.9"
}

variable "argocd_namespace" {
  description = "Namespace for Argo CD components."
  type        = string
  default     = "argocd"
}

variable "argocd_server_node_port" {
  description = "NodePort to expose the Argo CD server service."
  type        = number
  default     = 30080
}

variable "hubble_ui_node_port" {
  description = "NodePort to expose the Hubble UI service."
  type        = number
  default     = 31235
}

variable "signoz_ui_host_port" {
  description = "Host port to expose the SigNoz UI service (via a NodePort mapped onto the kind control plane)."
  type        = number
  default     = 3301
}

variable "signoz_ui_node_port" {
  description = "NodePort to expose the SigNoz UI service."
  type        = number
  default     = 30301
}

variable "azure_auth_namespaces" {
  description = "Namespaces for the azure auth simulation workload (Frontend + Backend API) per environment."
  type        = map(string)
  default = {
    dev = "dev"
    uat = "uat"
  }
}

variable "azure_auth_gateway_namespace" {
  description = "Namespace for the shared Azure auth gateway (NGINX Gateway Fabric data plane + Service)."
  type        = string
  default     = "azure-auth-gateway"
}

variable "azure_entraid_namespace" {
  description = "Namespace for Keycloak (simulates Azure Entra ID as external identity provider)."
  type        = string
  default     = "azure-entraid-sim"
}

variable "azure_apim_namespace" {
  description = "Namespace for APIM simulator (simulates Azure API Management in private endpoint mode)."
  type        = string
  default     = "azure-apim-sim"
}

variable "azure_auth_oauth2_proxy_host_port" {
  description = "Host port to expose the azure auth simulation OAuth2 Proxy service."
  type        = number
  default     = 3007
}

variable "azure_auth_oauth2_proxy_host_port_uat" {
  description = "Host port to expose the azure auth simulation OAuth2 Proxy service (uat)."
  type        = number
  default     = 3008
}

variable "azure_auth_oauth2_proxy_node_port" {
  description = "NodePort to expose the azure auth simulation OAuth2 Proxy service."
  type        = number
  default     = 30075
}

variable "azure_auth_oauth2_proxy_node_port_uat" {
  description = "NodePort to expose the azure auth simulation OAuth2 Proxy service (uat)."
  type        = number
  default     = 30076
}

variable "azure_auth_gateway_host_port" {
  description = "Host port to expose the azure auth simulation gateway (dev)."
  type        = number
  default     = 443
}

variable "azure_auth_gateway_host_port_uat" {
  description = "Host port to expose the azure auth simulation gateway (uat)."
  type        = number
  default     = 3008
}

variable "azure_auth_gateway_node_port" {
  description = "NodePort to expose the azure auth simulation gateway (dev)."
  type        = number
  default     = 30070
}

variable "azure_auth_gateway_node_port_uat" {
  description = "NodePort to expose the azure auth simulation gateway (uat)."
  type        = number
  default     = 30071
}

variable "azure_auth_apim_host_port" {
  description = "Host port to expose the azure auth simulation APIM simulator."
  type        = number
  default     = 8082
}

variable "azure_auth_apim_node_port" {
  description = "NodePort to expose the azure auth simulation APIM simulator."
  type        = number
  default     = 30082
}

variable "azure_auth_api_host_port" {
  description = "Host port to expose the azure auth simulation FastAPI backend."
  type        = number
  default     = 8081
}

variable "azure_auth_api_node_port" {
  description = "NodePort to expose the azure auth simulation FastAPI backend."
  type        = number
  default     = 30081
}

variable "azure_auth_keycloak_host_port" {
  description = "Host port to expose Keycloak for azure auth simulation."
  type        = number
  default     = 8180
}

variable "azure_auth_keycloak_node_port" {
  description = "NodePort to expose Keycloak for azure auth simulation."
  type        = number
  default     = 30180
}

variable "gitea_http_node_port" {
  description = "NodePort for Gitea HTTP."
  type        = number
  default     = 30090
}

variable "gitea_ssh_node_port" {
  description = "NodePort for Gitea SSH."
  type        = number
  default     = 30022
}

variable "gitea_chart_version" {
  description = "Gitea Helm chart version to deploy via Argo CD."
  type        = string
  default     = "12.4.0"
}

variable "use_external_gitea" {
  description = "If true, use an external/hosted Gitea instance instead of deploying Gitea inside the cluster."
  type        = bool
  default     = false
}

variable "gitea_http_host" {
  description = "Host/IP for Gitea HTTP endpoint as reachable from the cluster."
  type        = string
  default     = "127.0.0.1"
}

variable "gitea_http_scheme" {
  description = "Scheme for Gitea HTTP endpoint (http or https)."
  type        = string
  default     = "http"
}

variable "gitea_http_port" {
  description = "Port for Gitea HTTP endpoint. For in-cluster, this is the NodePort (30090). For external, typically 3000."
  type        = number
  default     = 30090
}

variable "gitea_ssh_host" {
  description = "Host/IP for Gitea SSH endpoint. For in-cluster Gitea accessed locally, use 127.0.0.1."
  type        = string
  default     = "127.0.0.1"
}

variable "gitea_ssh_port" {
  description = "Port for external Gitea SSH endpoint."
  type        = number
  default     = 30022
}

variable "gitea_ssh_username" {
  description = "SSH username for interacting with external Gitea."
  type        = string
  default     = "git"
}

variable "gitea_http_host_local" {
  description = "Host/IP for Gitea HTTP endpoint as reachable from the host running Terraform."
  type        = string
  default     = "127.0.0.1"
}

variable "gitea_ssh_host_local" {
  description = "Host/IP for Gitea SSH endpoint as reachable from the host running Terraform."
  type        = string
  default     = "127.0.0.1"
}

variable "gitea_registry_host" {
  description = "Host:port for the Gitea container registry as reachable from Kind nodes (containerd). Use localhost:NodePort because containerd runs on nodes (not in pods) and cannot resolve Kubernetes DNS names."
  type        = string
  default     = "localhost:30090"
}

# -----------------------------------------------------------------------------
# Cluster-internal Gitea addresses (for pods running inside Kubernetes)
# These are used when running commands from inside the cluster, e.g., ArgoCD
# connecting to Gitea, or kubectl run for ssh-keyscan.
# -----------------------------------------------------------------------------

variable "gitea_ssh_host_cluster" {
  description = "Host for Gitea SSH as reachable from inside the cluster (Kubernetes service name)."
  type        = string
  default     = "gitea-ssh.gitea.svc.cluster.local"
}

variable "gitea_ssh_port_cluster" {
  description = "Port for Gitea SSH as reachable from inside the cluster."
  type        = number
  default     = 22
}

variable "gitea_http_host_cluster" {
  description = "Host for Gitea HTTP as reachable from inside the cluster (Kubernetes service name)."
  type        = string
  default     = "gitea-http.gitea.svc.cluster.local"
}

variable "gitea_http_port_cluster" {
  description = "Port for Gitea HTTP as reachable from inside the cluster."
  type        = number
  default     = 3000
}

variable "gitea_admin_username" {
  description = "Gitea admin username."
  type        = string
  default     = "gitea-admin"
}

variable "gitea_admin_pwd" {
  description = "Gitea admin password (local dev). Defaults to ChangeMe123! for local convenience; override via TF_VAR_gitea_admin_pwd if desired."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "generate_repo_ssh_key" {
  description = "Generate an SSH keypair for Argo CD git access."
  type        = bool
  default     = true
}

variable "ssh_private_key_path" {
  description = "Path to write the generated SSH private key (gitignored)."
  type        = string
  default     = "./.run/argocd-repo.id_ed25519"
}

variable "ssh_public_key_path" {
  description = "Path to write the generated SSH public key."
  type        = string
  default     = "./.run/argocd-repo.id_ed25519.pub"
}

# -----------------------------------------------------------------------------
# Feature toggles for staged deployment
# -----------------------------------------------------------------------------

variable "enable_cilium" {
  description = "Enable Cilium CNI installation."
  type        = bool
  default     = true
}

variable "enable_hubble" {
  description = "Enable Hubble UI (requires enable_cilium = true)."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_hubble || var.enable_cilium
    error_message = "enable_hubble requires enable_cilium to be true, as Hubble is a component of Cilium."
  }
}

variable "enable_namespaces" {
  description = "Enable creation of Kubernetes namespaces."
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Enable Argo CD installation."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_argocd || var.enable_namespaces
    error_message = "enable_argocd requires enable_namespaces to be true, as the argocd namespace must be created first."
  }
}

variable "enable_gitea" {
  description = "Enable Gitea installation and repository setup."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_gitea || var.enable_argocd
    error_message = "enable_gitea requires enable_argocd to be true, as Argo CD consumes the repo."
  }
}

variable "enable_policies" {
  description = "Enable Cilium and Kyverno policy deployment (requires enable_gitea = true)."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_policies || var.enable_gitea
    error_message = "enable_policies requires enable_gitea to be true, as policies are sourced from the Gitea repository."
  }
}

variable "enable_victoria_metrics" {
  description = "Enable VictoriaMetrics stack deployment via app-of-apps. Disabled by default to avoid overloading local kind control plane."
  type        = bool
  default     = false
}

variable "enable_signoz" {
  description = "Enable SigNoz stack deployment via app-of-apps. Disabled by default to avoid overloading local kind control plane."
  type        = bool
  default     = false
}

variable "enable_signoz_k8s_infra" {
  description = "Enable SigNoz k8s-infra collection (in-cluster OpenTelemetry agents) to monitor the kind cluster. Disabled by default for local stability."
  type        = bool
  default     = false
}

variable "enable_actions_runner" {
  description = "Deploy a Gitea Actions runner (requires enable_gitea = true)."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_actions_runner || var.enable_gitea
    error_message = "enable_actions_runner requires enable_gitea to be true."
  }
}

variable "enable_docker_socket_mount" {
  description = "Mount the host Docker socket into Kind nodes so the in-cluster Actions runner can build images via the host daemon. Keep this consistent across stages to avoid Kind cluster replacement."
  type        = bool
  default     = true
}

variable "enable_azure_auth_sim" {
  description = "Enable deployment of the azure auth simulation (Keycloak + OAuth2 Proxy + APIM simulator + protected frontend)."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_azure_auth_sim || (var.enable_gitea && var.enable_argocd)
    error_message = "enable_azure_auth_sim requires enable_gitea and enable_argocd to be true because the workload is deployed via Argo CD from the seeded repository."
  }
}

variable "enable_subnetcalc_azure_auth_sim" {
  description = "Deploy the subnet calculator demo workloads (dev/uat) that sit behind the azure-auth-gateway/APIM simulator stack. Set false to keep the gateway/APIM platform while disabling the subnetcalc demo apps."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_subnetcalc_azure_auth_sim || var.enable_azure_auth_sim
    error_message = "enable_subnetcalc_azure_auth_sim requires enable_azure_auth_sim to be true."
  }
}

variable "enable_azure_entraid_sim" {
  description = "Deploy the Keycloak-based Entra ID simulator used by oauth2-proxy OIDC flows."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_azure_entraid_sim || var.enable_azure_auth_sim
    error_message = "enable_azure_entraid_sim requires enable_azure_auth_sim to be true."
  }
}

variable "enable_platform_sso" {
  description = "Enable platform SSO (ArgoCD + Gitea + SigNoz) using the Entra ID simulator (Keycloak)."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_platform_sso || (var.enable_azure_auth_sim && var.enable_azure_entraid_sim)
    error_message = "enable_platform_sso requires enable_azure_auth_sim and enable_azure_entraid_sim to be true."
  }
}

variable "preload_kind_images" {
  description = "Pre-pull and 'kind load' large images (e.g., Keycloak) into the kind nodes right after cluster creation to avoid slow in-cluster image pulls."
  type        = bool
  default     = true
}

variable "keycloak_container_image" {
  description = "Keycloak container image to preload into kind nodes (must match the image used by the azure-entraid-sim manifests)."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.4.7"
}

variable "platform_sso_keycloak_host" {
  description = "External hostname (via Gateway API) used for Keycloak OIDC endpoints."
  type        = string
  default     = "login.127.0.0.1.sslip.io"
}

variable "argocd_oidc_client_id" {
  description = "Keycloak OIDC client ID for ArgoCD."
  type        = string
  default     = "argocd"
}

variable "argocd_oidc_client_secret" {
  description = "Keycloak OIDC client secret for ArgoCD (local dev only)."
  type        = string
  default     = "argocd-secret"
}

variable "gitea_oidc_client_id" {
  description = "Keycloak OIDC client ID for Gitea."
  type        = string
  default     = "gitea"
}

variable "gitea_oidc_client_secret" {
  description = "Keycloak OIDC client secret for Gitea (local dev only)."
  type        = string
  default     = "gitea-secret"
}

variable "enable_sentiment_auth_frontend" {
  description = "Deploy the sentiment authenticated frontend (oauth2-proxy forced login + React UI) and seed the build pipeline into Gitea."
  type        = bool
  default     = false

  validation {
    condition = !var.enable_sentiment_auth_frontend || (
      var.enable_gitea &&
      var.enable_argocd &&
      var.enable_actions_runner &&
      var.enable_azure_auth_sim &&
      var.enable_azure_entraid_sim
    )
    error_message = "enable_sentiment_auth_frontend requires enable_gitea, enable_argocd, enable_actions_runner, enable_azure_auth_sim, and enable_azure_entraid_sim to be true."
  }
}

variable "enable_llm_sentiment" {
  description = "Enable deployment of the local LLM sentiment demo (Ollama + minimal API + dev/uat frontends via APIM simulator) via app-of-apps."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_llm_sentiment || (var.enable_gitea && var.enable_argocd)
    error_message = "enable_llm_sentiment requires enable_gitea and enable_argocd to be true because the workload is deployed via Argo CD from the seeded repository."
  }
}

variable "azure_auth_sim_use_sidecar" {
  description = "Use the sidecar deployment pattern (unused in multi-env overlays)."
  type        = bool
  default     = false
}

variable "enable_azure_auth_ports" {
  description = "Expose azure auth simulation NodePorts/host ports on the kind control plane. Keep this true from stage 100 onward to avoid cluster recreation when enabling the workload later."
  type        = bool
  default     = false
}

variable "docker_socket_path" {
  description = "Path to Docker socket on the host for in-cluster Actions runner. Default '/var/run/docker.sock' works on Linux and macOS with Docker Desktop. WARNING: Mounting the Docker socket grants full host Docker access - use only in trusted local development environments."
  type        = string
  default     = "/var/run/docker.sock"
}

variable "actions_runner_image" {
  description = "Container image for the Gitea Actions runner. Pinned to specific version for reproducibility."
  type        = string
  default     = "gitea/act_runner:0.2.13"
}
