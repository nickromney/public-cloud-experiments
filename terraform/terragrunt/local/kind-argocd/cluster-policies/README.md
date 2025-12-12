Policies synchronized via Argo CD from the local Gitea repository (created by Terraform). This directory is staged under `cluster-policies/` in the `policies` repo and represents the cluster-wide controls.

- `cilium/` enforces ingress/egress for the azure-auth workloads across namespaces (nginx-gateway, APIM, Keycloak, frontend/api).
- `kyverno/` provides default-deny scaffolding; customize via labels to allow intended paths.

App-specific manifests and policies reside under `apps/<app>/` in the same repo. Publish changes here to the in-cluster `policies` repo via `terraform/terragrunt/local/kind-argocd/scripts/sync-gitea.sh`.
