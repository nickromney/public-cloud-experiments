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

          # Scrape selected Prometheus endpoints and ship into SigNoz.
          # This is the easiest way to surface Cilium mesh-auth / policy metrics.
          prometheus:
            enabled: true
            scrapeInterval: 30s
            scrapeConfigs:
              - job_name: cilium-agent
                kubernetes_sd_configs:
                  - role: pod
                    namespaces:
                      names: ["kube-system"]
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_label_k8s_app]
                    action: keep
                    regex: cilium
                  - source_labels: [__meta_kubernetes_pod_ip]
                    action: replace
                    target_label: __address__
                    regex: (.+)
                    replacement: $1:9962
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
