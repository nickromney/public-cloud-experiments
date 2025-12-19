apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sentiment-auth-uat
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: uat
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/sentiment-auth/overlays/uat
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
