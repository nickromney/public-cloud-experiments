Policies synchronized via Argo CD from the local Gitea repository (created by Terraform):

- `cilium/` isolates namespaces `cilium-team-a` and `cilium-team-b` (intra-namespace only; DNS + apiserver allowed).
- `kyverno/` generates a default-deny NetworkPolicy for any namespace labeled `kyverno.io/isolate=true` (example: `kyverno-sandbox`).
