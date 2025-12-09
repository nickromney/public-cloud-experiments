# ArgoCD Application for Azure Auth Simulation
# Generated from template - URLs configured via Terraform variables
#
# Deployment patterns:
#   - Default (5 pods): apps/azure-auth-sim
#   - Sidecar (4 pods): apps/azure-auth-sim/overlays/sidecar
#
# Set azure_auth_sim_use_sidecar = true in tfvars to use sidecar pattern
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: azure-auth-sim
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: azure-auth-sim
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: ${use_sidecar ? "apps/azure-auth-sim/overlays/sidecar" : "apps/azure-auth-sim"}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
