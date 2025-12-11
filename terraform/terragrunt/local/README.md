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
- deploys the "azure auth simulation" across three namespaces simulating Azure production topology:
  - `azure-auth-sim`: Frontend + OAuth2-Proxy, Backend API (simulates AKS workloads)
  - `azure-entraid-sim`: Keycloak (simulates Azure Entra ID as external identity provider)
  - `azure-apim-sim`: APIM Simulator with Gateway (simulates Azure APIM in private endpoint mode with Application Gateway)
- runs `apps/nginx-gateway-fabric` to install NGINX Gateway Fabric (GatewayClass, controller, and proxy) so the gateway becomes the sole external surface for the azure-auth-sim stack
- the protected frontend entrypoint is reachable through NGINX Gateway Fabric on `http://localhost:3007`; APIM external endpoint available at `http://apim.localhost` (requires /etc/hosts entry)
- seeds a `policies` repo in Gitea over SSH, captures the SSH host key, and registers the repo in Argo CD with strict host-key checking
- Argo CD Applications:
  - `gitea` (Helm)
  - `cilium-policies` (Gitea repo path `cluster-policies/cilium/`)
  - `kyverno` (Helm)
  - `kyverno-policies` (Gitea repo path `cluster-policies/kyverno/`)
  - `nginx-gateway-fabric` (Gitea repo path `apps/nginx-gateway-fabric`)
  - `azure-auth-sim` (Gitea repo path `apps/azure-auth-sim`)
  - `azure-entraid-sim` (Gitea repo path `apps/azure-entraid-sim`)
  - `azure-apim-sim` (Gitea repo path `apps/azure-apim-sim`)
- Namespaces created: `gitea`, `cilium-team-a`, `cilium-team-b`, `kyverno`, `kyverno-sandbox`, `nginx-gateway`, `azure-auth-sim`, `azure-entraid-sim`, `azure-apim-sim`

## Usage

Stages are cumulative `.tfvars` files that progressively enable features. Each stage includes all features from previous stages.

```bash
# From terraform/terragrunt/local/kind-argocd directory
terragrunt apply -var-file=stages/100-kind.tfvars           # Kind cluster only
terragrunt apply -var-file=stages/200-cilium.tfvars         # + Cilium CNI
terragrunt apply -var-file=stages/300-hubble.tfvars         # + Hubble UI
terragrunt apply -var-file=stages/400-argocd.tfvars         # + Namespaces + Argo CD
terragrunt apply -var-file=stages/500-gitea.tfvars          # + Gitea
terragrunt apply -var-file=stages/600-policies.tfvars       # + Cilium/Kyverno policies
terragrunt apply -var-file=stages/700-azure-auth-sim.tfvars # + Azure auth simulation (full stack)
```

| Stage | Enables                                  |
| ----- | ---------------------------------------- |
| 100   | Kind cluster (no CNI)                    |
| 200   | + Cilium                                 |
| 300   | + Hubble UI                              |
| 400   | + Namespaces + Argo CD                   |
| 500   | + Gitea                                  |
| 600   | + Cilium/Kyverno policies                |
| 700   | + Azure auth simulation + Actions runner |

All state and generated artifacts stay under `terraform/terragrunt/.run/local/kind-argocd/` (state) and `terraform/terragrunt/local/kind-argocd/.run/` (SSH keys, known_hosts), both gitignored. Kubeconfig is written to `~/.kube/config` by default.

### Azure auth simulation (stage 700)

Stage 700 enables the full azure-auth-sim workload which simulates Azure authentication patterns:

- **azure-auth-sim namespace**: Frontend (with OAuth2-Proxy sidecar) + Backend API (simulates AKS workloads)
- **azure-entraid-sim namespace**: Keycloak (simulates Azure Entra ID as external identity provider)
- **azure-apim-sim namespace**: APIM Simulator with Gateway (simulates Azure APIM in private endpoint mode with Application Gateway)

The Actions runner builds container images from source using Gitea Actions and pushes them to the Gitea container registry. Argo CD then deploys the workload from the seeded repository.

## Access and debugging

- Cluster: `kubectl get nodes` (kubeconfig written to `~/.kube/config`)
- Argo CD UI: `https://localhost:30080` (self-signed). Login with:
  - user: `admin`
  - password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- Hubble UI: `http://localhost:31235/?namespace=kube-system`
- Logs: `kubectl -n kube-system logs -l k8s-app=cilium --tail=200` and `kubectl -n kube-system logs deploy/cilium-hubble-relay --tail=200`
- Gitea UI: `http://localhost:30090` (defaults `gitea-admin` / `ChangeMe123!`). SSH: `ssh://git@localhost:30022/<user>/policies.git`
- Azure auth simulation:
  - Protected frontend entry: `http://localhost:3007` (served through NGINX Gateway Fabric; gateway routes traffic to the oauth2-proxy pod)
  - External APIM endpoint: `http://apim.localhost` (requires `/etc/hosts` entry: `127.0.0.1 apim.localhost`)
  - Services are distributed across namespaces:
    - `azure-auth-sim`: Frontend, Backend API
    - `azure-entraid-sim`: Keycloak
    - `azure-apim-sim`: APIM Simulator
  - Port-forward for debugging: `kubectl -n <namespace> port-forward svc/<name> <port>`

## Argo CD applications (GitOps)

- Gitea (Helm chart)
- Cilium policies (from Gitea repo `cluster-policies/cilium`): isolates `cilium-team-a` and `cilium-team-b` (intra-namespace only; DNS + apiserver allowed)
- Kyverno (Helm)
- Kyverno policies (from Gitea repo `cluster-policies/kyverno`): generates default-deny `NetworkPolicy` for namespaces labeled `kyverno.io/isolate=true` (example `kyverno-sandbox`)
- NGINX Gateway Fabric (from Gitea repo `apps/nginx-gateway-fabric`): installs the Gateway controller, `GatewayClass`, and proxy so the gateway service becomes the only external ingress for the azure-auth stack
- Azure auth simulation (three ArgoCD Applications):
  - `azure-auth-sim`: Frontend + OAuth2-Proxy, Backend API (AKS workloads)
  - `azure-entraid-sim`: Keycloak (Azure Entra ID simulation)
  - `azure-apim-sim`: APIM Simulator with external Gateway (Azure APIM + Application Gateway simulation)

## How it wires together

- Terraform installs Argo CD and Cilium, waits for Gitea rollout, creates the `policies` repo in Gitea, pushes policy files from this repo into Gitea, captures the Gitea SSH host key via `ssh-keyscan`, and registers the repo in Argo CD with `sshKnownHosts` (no insecure SSH).
- Argo CD syncs the applications listed above.
- The seeded `policies` repo keeps cluster-wide controls under `cluster-policies/` (synced by the `cilium-policies`/`kyverno-policies` apps) and each workload under `apps/<name>/` so per-app manifests and scoped policies (e.g., `apps/azure-auth-sim/policies/cilium/cilium-network-policies.yaml`) live together.
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
