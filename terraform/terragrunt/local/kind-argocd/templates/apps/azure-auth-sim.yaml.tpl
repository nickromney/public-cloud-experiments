# ArgoCD Application for Azure Auth Simulation
# Generated from template - URLs configured via Terraform variables
#
# Deployment patterns:
#   - Overlays per env (dev/uat) under apps/azure-auth-sim/overlays/<env>
# Sidecar overlay is not used in this multi-env setup (frontend already carries oauth2-proxy sidecar).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: azure-auth-${env_name}
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${azure_auth_namespace}
    server: https://kubernetes.default.svc
  ignoreDifferences:
    - group: ""
      kind: Service
      namespace: ${azure_auth_namespace}
      name: azure-auth-gateway-nginx
      jsonPointers:
        - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
        - /metadata/annotations/metallb.universe.tf~1ip-allocated-from-pool
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
    path: "apps/azure-auth-sim/overlays/${env_name}"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
