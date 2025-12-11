# ArgoCD Application for Kyverno Policies
# Generated from template - URLs configured via Terraform variables
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno-policies
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: cluster-policies/kyverno
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
