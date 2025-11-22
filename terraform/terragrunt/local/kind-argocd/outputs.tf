output "kubeconfig_path" {
  description = "Path to the kubeconfig generated for the kind cluster."
  value       = var.kubeconfig_path
}

output "kind_config_path" {
  description = "Path to the rendered kind cluster configuration."
  value       = var.kind_config_path
}

output "argocd_server_node_port" {
  description = "NodePort exposing the Argo CD API server."
  value       = var.argocd_server_node_port
}

output "hubble_ui_node_port" {
  description = "NodePort exposing the Hubble UI."
  value       = var.hubble_ui_node_port
}

output "ssh_public_key" {
  description = "Public key for Git/ArgoCD SSH access (add to your repo hosting)."
  value       = try(tls_private_key.argocd_repo[0].public_key_openssh, null)
}

output "ssh_private_key_path" {
  description = "Location of the generated SSH private key."
  value       = var.ssh_private_key_path
  sensitive   = true
}
