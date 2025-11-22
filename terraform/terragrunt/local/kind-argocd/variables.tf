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
  description = "Kind node image (supports Apple Silicon when using podman)."
  type        = string
  default     = "kindest/node:v1.29.2"
}

variable "kind_config_path" {
  description = "Path to write the rendered kind cluster config."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to write the kubeconfig for the cluster."
  type        = string
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
  default     = 30007
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

variable "gitea_admin_username" {
  description = "Gitea admin username."
  type        = string
  default     = "gitea-admin"
}

variable "gitea_admin_password" {
  description = "Gitea admin password."
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
  description = "Enable Cilium CNI installation (includes Hubble)."
  type        = bool
  default     = true
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
}

variable "enable_gitea" {
  description = "Enable Gitea and policy seeding."
  type        = bool
  default     = true
}
