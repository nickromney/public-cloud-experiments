# Local Terragrunt Context (kind + ArgoCD + Cilium + Gitea + Kyverno)

This context provisions a five-node kind cluster on Podman (Apple Silicon friendly), installs Argo CD via Helm, wires in Cilium 1.18.4 with Hubble UI, uses an external Gitea (Podman/Docker compose) to host the repos, optionally deploys the “azure auth simulation” workload, and syncs Cilium/Kyverno policies via Argo CD. OpenTofu is used automatically via `root-local.hcl`.

## Prerequisites

- Podman with the kind provider enabled (`kind` CLI available)
- kubectl/kubectx/kubens
- Helm
- OpenTofu (`tofu`) and Terragrunt on PATH
- `ssh-keyscan` available (for Gitea SSH host key capture)

## Stack layout

`terraform/terragrunt/local/kind-argocd`

- renders `kind-config.yaml` (1x control plane + 4x workers, CNI disabled so Cilium can install)
- writes kubeconfig to `~/.kube/config`
- installs Cilium + Hubble UI (NodePort `31235`)
- installs Argo CD (NodePort `30080`)
- installs Gitea (HTTP NodePort `30090`, SSH NodePort `30022`)
- deploys the “azure auth simulation” app (`apps/azure-auth-sim`, Argo CD Application `azure-auth-sim`) which runs OAuth2 Proxy + Keycloak + APIM simulator + FastAPI backend + protected React frontend; exposed on:
  - OAuth2 Proxy / protected frontend entry: http://localhost:3007
  - Keycloak: http://localhost:8180
  - APIM simulator: http://localhost:8082
  - FastAPI backend: http://localhost:8081
- seeds a `policies` repo in Gitea over SSH, captures the SSH host key, and registers the repo in Argo CD with strict host-key checking
- Argo CD Applications:
  - `gitea` (Helm)
  - `cilium-policies` (Gitea repo path `cilium/`)
  - `kyverno` (Helm)
  - `kyverno-policies` (Gitea repo path `kyverno/`)
  - `azure-auth-sim` (Gitea repo path `apps/azure-auth-sim`, deploys OAuth2 Proxy + Keycloak + APIM simulator + protected React frontend)
- Namespaces created: `gitea`, `cilium-team-a`, `cilium-team-b`, `kyverno`, `kyverno-sandbox`

## Usage

```bash
# From repo root (external Gitea will be auto-started via compose if not running)
make local kind 100                        # start external Gitea + seed repos
make local kind 200                        # trigger CI build/push for azure-auth images (host runner)
make local kind 300 apply AUTO_APPROVE=1   # create kind cluster
make local kind 400 apply AUTO_APPROVE=1   # install Cilium
make local kind 500 apply AUTO_APPROVE=1   # enable Hubble UI
make local kind 600 apply AUTO_APPROVE=1   # namespaces + Argo CD
make local kind 700 apply AUTO_APPROVE=1   # policies (optional)
make local kind 800 apply AUTO_APPROVE=1   # (reserved)
make local kind 900 apply AUTO_APPROVE=1   # azure-auth-sim (expects images built via CI)
```

All state and generated artifacts stay under `terraform/terragrunt/.run/local/kind-argocd/` (state) and `terraform/terragrunt/local/kind-argocd/.run/` (SSH keys, known_hosts), both gitignored. Kubeconfig is written to `~/.kube/config` by default.

### Azure auth simulation images (former “stack 12”)

Stage `700` builds the API, APIM simulator, and protected frontend from source using Gitea Actions (host runner) and pushes them to the external Gitea container registry. Argo CD then deploys the workload from the repo seeded by Terragrunt. The legacy `make local kind prereqs` helper still exists for manual, local image builds but is no longer run automatically. Experiments and caveats for the host-runner/DinD path are captured in `kind-argocd/EXPERIMENTS.md`.

## Access and debugging

- Cluster: `kubectl get nodes` (kubeconfig written to `~/.kube/config`)
- Argo CD UI: https://localhost:30080 (self-signed). Login with:
  - user: `admin`
  - password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- Hubble UI: http://localhost:31235/?namespace=kube-system
- Logs: `kubectl -n kube-system logs -l k8s-app=cilium --tail=200` and `kubectl -n kube-system logs deploy/cilium-hubble-relay --tail=200`
- Gitea UI: http://localhost:30090 (defaults `gitea-admin` / `ChangeMe123!`). SSH: `ssh://git@localhost:30022/<user>/policies.git`
- Azure auth simulation:
  - OAuth2 Proxy / protected frontend: http://localhost:3007
  - Keycloak: http://localhost:8180
  - APIM simulator: http://localhost:8082
  - FastAPI backend: http://localhost:8081

## Argo CD applications (GitOps)

- Gitea (Helm chart)
- Cilium policies (from Gitea repo `policies/cilium`): isolates `cilium-team-a` and `cilium-team-b` (intra-namespace only; DNS + apiserver allowed)
- Kyverno (Helm)
- Kyverno policies (from Gitea repo `policies/kyverno`): generates default-deny `NetworkPolicy` for namespaces labeled `kyverno.io/isolate=true` (example `kyverno-sandbox`)

## How it wires together

- Terraform installs Argo CD and Cilium, waits for Gitea rollout, creates the `policies` repo in Gitea, pushes policy files from this repo into Gitea, captures the Gitea SSH host key via `ssh-keyscan`, and registers the repo in Argo CD with `sshKnownHosts` (no insecure SSH).
- Argo CD syncs the four Applications above.
- CiliumNetworkPolicies isolate team namespaces; Kyverno generates NetworkPolicy for any namespace labeled `kyverno.io/isolate=true`.

## Reproducible test steps

1) Apply: `terragrunt apply`
2) (Optional) Merge kubeconfig: `KUBECONFIG=$HOME/.kube/config:.run/kubeconfig kubectl config view --flatten > /tmp/kubeconfig && mv /tmp/kubeconfig $HOME/.kube/config`
3) Verify cluster: `kubectl get nodes`
4) Verify Argo CD apps: `kubectl -n argocd get applications`
5) Verify Cilium: `kubectl -n kube-system get pods -l k8s-app=cilium`
6) Verify Kyverno: `kubectl -n kyverno get pods`
7) Check policies synced:
   - `kubectl -n cilium-team-a get ciliumnetworkpolicies`
   - `kubectl -n cilium-team-b get ciliumnetworkpolicies`
   - `kubectl -n kyverno-sandbox get networkpolicies`
8) Optional access:
   - Gitea UI `http://localhost:30090`
   - Argo CD UI `https://localhost:30080` (see admin password command above)
   - Hubble UI `http://localhost:31235`
   - Azure auth simulation entrypoint `http://localhost:3007`

## Notes on SSH

- Repo URL used by Argo CD: `ssh://git@127.0.0.1:30022/<admin>/policies.git`
- Host key is captured with `ssh-keyscan` to `.run/gitea_known_hosts` and injected into the Argo CD repo Secret (`repo-gitea-policies`), with `insecure=false`.
