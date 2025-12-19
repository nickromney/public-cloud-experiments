# Kyverno policy engine - deployed via Helm
# Namespace is created by Terraform; ArgoCD only manages the release
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  source:
    repoURL: https://kyverno.github.io/kyverno/
    chart: kyverno
    targetRevision: 3.2.7
    helm:
      releaseName: kyverno
      values: |
        crds:
          install: true
        admissionController:
          replicas: 1
        backgroundController:
          replicas: 1
        cleanupController:
          replicas: 1
        cleanupJobs:
          admissionReports:
            enabled: false
          clusterAdmissionReports:
            enabled: false
          ephemeralReports:
            enabled: false
          clusterEphemeralReports:
            enabled: false
          updateRequests:
            enabled: false
        webhooksCleanup:
          enabled: false
        policyReportsCleanup:
          enabled: false
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
