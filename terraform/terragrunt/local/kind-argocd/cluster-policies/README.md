Policies synchronized via Argo CD from the local Gitea repository (created by Terraform). This directory is staged under `cluster-policies/` in the `policies` repo and represents the cluster-wide controls.

- `cilium/` isolates namespaces `cilium-team-a` and `cilium-team-b` (intra-namespace only; DNS + apiserver allowed).
- `kyverno/` generates a default-deny NetworkPolicy for any namespace labeled `kyverno.io/isolate=true` (example: `kyverno-sandbox`).

App-specific manifests and policies reside under `apps/<app>/` in the same repo (Azure auth simulation keeps its scoped Cilium policy under `apps/azure-auth-sim/policies/cilium/cilium-network-policies.yaml`).
