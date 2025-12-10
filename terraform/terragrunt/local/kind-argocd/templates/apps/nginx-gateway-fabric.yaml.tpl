# ArgoCD Application for NGINX Gateway Fabric
# Generated from template - URLs configured via Terraform variables
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-gateway-fabric
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: nginx-gateway
    server: https://kubernetes.default.svc
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/nginx-gateway-fabric
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - ServerSideApply=true
