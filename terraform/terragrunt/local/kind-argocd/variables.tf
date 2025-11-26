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
  default     = 31235
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
    error_message = "enable_gitea requires enable_argocd to be true, as Gitea is deployed via Argo CD."
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
