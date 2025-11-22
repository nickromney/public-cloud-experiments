## Current status (local/kind-argocd)

- New Terragrunt context under `terraform/terragrunt/local/kind-argocd` adds a local kind stack (control-plane + 4 workers), Cilium 1.18.4 + Hubble UI, Argo CD, Gitea via Argo CD, and GitOps of Cilium/Kyverno policies pushed into a local Gitea repo over SSH. Policies live in `policies/` (Cilium namespace isolation; Kyverno default-deny for `kyverno.io/isolate=true` namespaces).
- Providers are kubeconfig-based; Argo CD Applications use `kubectl_manifest` to avoid CRD bootstrap ordering issues. Kind config renders NodePort host port mappings (Argo CD 30080, Gitea 30090/30022, Hubble UI 30007).
- README at `terraform/terragrunt/local/README.md` describes usage/tests.
- Podman machine connectivity became unstable; repeated applies tainted/destroyed the cluster. Last successful state had a running cluster, but a subsequent `kind delete cluster --name kind-local` removed it. Current apply was aborted part-way; cluster does **not** exist. State files are in `terraform/terragrunt/.run/local/kind-argocd/` (and a `.pre-rebuild` backup).

## Known issues / investigation needed

- Podman connection intermittently fails (`ssh handshake failed: EOF`). Verify `podman machine start` works and that `podman ps` is responsive before applying.
- Re-applying from scratch may fail if stale kind nodes exist; delete with `kind delete cluster --name kind-local` before re-run. State may also be partially tainted; consider moving current state aside if apply keeps failing.
- Gitea readiness previously blocked automation (valkey instability/HTTP 000). After chart tweaks it started once, but subsequent rebuilds never completed because apply was interrupted. Need to validate Gitea comes up and API reachable on NodePort 30090.
- Kyverno CRDs: Helm values changed to `crds.install: true`; verify Kyverno pods become healthy after Argo CD sync.

## How to resume

1) Ensure Podman machine is healthy:
   - `podman machine start podman-machine-default` (already created, rootful)
   - `podman ps` should work; if not, stop/start the machine again.
2) Clean slate for kind: `kind delete cluster --name kind-local` (if exists).
3) From `terraform/terragrunt/local/kind-argocd` run:
   - `terragrunt init`
   - `terragrunt apply -auto-approve`
   If state errors persist, temporarily move `terraform/terragrunt/.run/local/kind-argocd/terraform.tfstate` aside and re-apply fresh.
4) After apply, verify:
   - `KUBECONFIG=./.run/kubeconfig kubectl get nodes`
   - `kubectl -n argocd get applications`
   - Gitea HTTP `curl -I http://127.0.0.1:30090` and SSH `ssh-keyscan -p 30022 127.0.0.1`
5) If Gitea repo seeding fails, check logs: `kubectl -n gitea logs deploy/gitea`; re-run apply once Gitea is healthy (null_resources will retry).
6) Sync Argo CD apps if needed: `kubectl -n argocd app sync gitea cilium-policies kyverno kyverno-policies`.

## Commit guidance

- Commit includes new local context files, templates, policies, README, and `.gitignore` update for `.run/`. Example message:
  - `feat(local): add kind/cilium/argocd/gitea terragrunt stack`
- Mention prerequisites (Podman/kind), ports (30080/30090/30022/30007), and that apply seeds policies into Gitea over SSH with host-key verification.
