# ArgoCD Application for Azure APIM Simulation
# Generated from template - URLs configured via Terraform variables
#
# This namespace simulates Azure API Management in private endpoint mode
# with an Application Gateway providing internal/external listeners
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: azure-apim-sim
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${azure_apim_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/azure-apim-sim
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
