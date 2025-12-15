# Namespace is created by Terraform; ArgoCD only manages the release
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: signoz-k8s-infra
  namespace: ${argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: https://charts.signoz.io
    chart: k8s-infra
    targetRevision: 0.15.0
    helm:
      releaseName: signoz-k8s-infra
      values: |
        clusterName: "${cluster_name}"
        # Export cluster telemetry (metrics/events) to the in-cluster SigNoz collector.
        otelCollectorEndpoint: signoz-otel-collector.observability.svc.cluster.local:4317
        otelInsecure: true

        presets:
          # Turnkey UX: enable pod logs so SigNoz immediately shows cluster workloads (e.g. subnetcalc pods).
          logsCollection:
            enabled: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
