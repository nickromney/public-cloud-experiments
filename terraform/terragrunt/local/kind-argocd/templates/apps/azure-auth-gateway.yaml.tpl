apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: azure-auth-gateway
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${azure_auth_gateway_namespace}
    server: https://kubernetes.default.svc
  ignoreDifferences:
    - group: ""
      kind: Service
      namespace: ${azure_auth_gateway_namespace}
      name: azure-auth-gateway-nginx
      jsonPointers:
        - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
        - /spec/clusterIP
        - /spec/clusterIPs
        - /spec/ipFamilies
        - /spec/ipFamilyPolicy
        - /spec/sessionAffinity
        - /spec/allocateLoadBalancerNodePorts
        - /status
  source:
    repoURL: ssh://${gitea_ssh_username}@${gitea_ssh_host}:${gitea_ssh_port}/${gitea_admin_username}/policies.git
    targetRevision: main
    path: apps/azure-auth-gateway
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
