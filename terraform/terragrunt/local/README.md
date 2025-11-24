# Local Terragrunt Context (kind + ArgoCD + Cilium + Gitea + Kyverno)

This context provisions a five-node kind cluster on Podman (Apple Silicon friendly), installs Argo CD via Helm, wires in Cilium 1.18.4 with Hubble UI, installs Gitea, seeds a policies repo over SSH, and syncs Cilium/Kyverno policies via Argo CD. OpenTofu is used automatically via `root-local.hcl`.

## Prerequisites

- Podman with the kind provider enabled (`kind` CLI available)
- kubectl/kubectx/kubens
- Helm
- OpenTofu (`tofu`) and Terragrunt on PATH
- `ssh-keyscan` available (for Gitea SSH host key capture)

## Stack layout

`terraform/terragrunt/local/kind-argocd`

- renders `kind-config.yaml` (1x control plane + 4x workers, CNI disabled so Cilium can install)
- writes kubeconfig to `.run/kubeconfig`
- installs Cilium + Hubble UI (NodePort `30007`)
- installs Argo CD (NodePort `30080`)
- installs Gitea (HTTP NodePort `30090`, SSH NodePort `30022`)
- seeds a `policies` repo in Gitea over SSH, captures the SSH host key, and registers the repo in Argo CD with strict host-key checking
- Argo CD Applications:
  - `gitea` (Helm)
  - `cilium-policies` (Gitea repo path `cilium/`)
  - `kyverno` (Helm)
  - `kyverno-policies` (Gitea repo path `kyverno/`)
- Namespaces created: `gitea`, `cilium-team-a`, `cilium-team-b`, `kyverno`, `kyverno-sandbox`

## Usage

```bash
cd terraform/terragrunt/local/kind-argocd
terragrunt init
terragrunt plan
terragrunt apply   # creates cluster, installs charts, seeds Gitea repo, registers Argo CD apps
```

All state and generated artifacts stay under `terraform/terragrunt/.run/local/kind-argocd/` (state) and `terraform/terragrunt/local/kind-argocd/.run/` (kubeconfig/SSH keys, known_hosts), both gitignored.

## Access and debugging

- `KUBECONFIG=./.run/kubeconfig kubectl get nodes`
- Argo CD UI: port-forward `kubectl -n argocd port-forward svc/argocd-server 8080:80` or use NodePort `30080`
- Hubble UI: `kubectl -n kube-system port-forward svc/hubble-ui 12000:80`
- Logs: `kubectl -n kube-system logs -l k8s-app=cilium --tail=200` and `kubectl -n kube-system logs deploy/cilium-hubble-relay --tail=200`
- Gitea UI: `http://127.0.0.1:30090` (admin user/pass in `variables.tf`; defaults `gitea-admin` / `ChangeMe123!`). SSH clone: `ssh://git@127.0.0.1:30022/<user>/policies.git`

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
   - Gitea UI `http://127.0.0.1:30090`
   - Argo CD UI via port-forward `kubectl -n argocd port-forward svc/argocd-server 8080:80`

## Notes on SSH

- Repo URL used by Argo CD: `ssh://git@127.0.0.1:30022/<admin>/policies.git`
- Host key is captured with `ssh-keyscan` to `.run/gitea_known_hosts` and injected into the Argo CD repo Secret (`repo-gitea-policies`), with `insecure=false`.
