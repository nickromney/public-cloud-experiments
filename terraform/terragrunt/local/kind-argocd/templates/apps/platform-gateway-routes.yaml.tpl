apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-gateway-routes
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: gateway-routes
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/platform-gateway-routes
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
