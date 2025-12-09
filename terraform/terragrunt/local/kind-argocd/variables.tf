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
  default     = "kindest/node:v1.34.0"
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
  default     = "1.18.4"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version to install."
  type        = string
  default     = "7.5.2"
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

variable "azure_auth_namespace" {
  description = "Namespace for the azure auth simulation workload (Keycloak + OAuth2 Proxy + APIM simulator)."
  type        = string
  default     = "azure-auth-sim"
}

variable "azure_auth_oauth2_proxy_host_port" {
  description = "Host port to expose the azure auth simulation OAuth2 Proxy service."
  type        = number
  default     = 3007
}

variable "azure_auth_oauth2_proxy_node_port" {
  description = "NodePort to expose the azure auth simulation OAuth2 Proxy service."
  type        = number
  default     = 30070
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

variable "gitea_admin_password" {
  description = "Gitea admin password. WARNING: The default is insecure and only suitable for local development. Change this for any environment exposed to a network."
  type        = string
  default     = "ChangeMe123!"
  sensitive   = true
}

variable "generate_repo_ssh_key" {
  description = "Generate an SSH keypair for Argo CD git access."
  type        = bool
  default     = true
}

variable "ssh_private_key_path" {
  description = "Path to write the generated SSH private key (gitignored)."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to write the generated SSH public key."
  type        = string
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

variable "azure_auth_sim_use_sidecar" {
  description = "Use the sidecar deployment pattern (oauth2-proxy + frontend in same pod). When false, uses separate pods (default). See AZURE_AUTH_SIM.md for details."
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
