# ArgoCD Application for Azure Entra ID Simulation (Keycloak)
# Generated from template - URLs configured via Terraform variables
#
# This namespace simulates Azure Entra ID as an external identity provider
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: azure-entraid-sim
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${azure_entraid_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/azure-entraid-sim
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
