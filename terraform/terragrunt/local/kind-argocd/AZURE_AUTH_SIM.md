# Azure Auth Simulation (local AKS replica)

## Intent (per brief)
- Run a macOS kind cluster (now via Docker Desktop) mirroring the AKS + GitHub Actions setup used in Azure.
- Build the `stack12` Azure auth simulation images for linux/amd64 from an Apple Silicon host.
- Bring up Cilium + Hubble, Argo CD, Cilium/Kyverno policies, Argo CD app-of-apps, and finally the Azure auth simulation workload.
- Drive the flow with `make local kind 100` → `200` → `300 apply` → `400 apply` → `500 apply` → `600 apply` → `700 apply` → `900 apply` (AUTO_APPROVE=1 for applies).

## Current implementation in repo
- **Stage 100 (Gitea bootstrap)**: `terraform/terragrunt/local/kind-argocd/scripts/stage100-gitea.sh` starts external Gitea (Homebrew if available, otherwise `external-gitea-compose.yaml`), issues HTTPS certs for `localhost`/`host.docker.internal`, creates repos `policies` and `azure-auth-sim`, and seeds them. The Azure repo is built from `gitea-repos/azure-auth-sim` plus the subnet-calculator sources (`api-apim-simulator`, `api-fastapi-azure-function`, `frontend-react`, `shared-frontend`), so the workflow and app manifests are in place. SSH keys/known_hosts are written to `.run/`.
- **Stage 200 (CI build + push)**: `terraform/terragrunt/local/kind-argocd/scripts/stage200-build.sh` registers a host-runner (act_runner, executor=host) against Gitea and triggers `.gitea/workflows/azure-auth-sim.yaml`. The workflow pre-pulls base images with `--platform linux/amd64`, builds/pushes `azure-auth-sim-{api,apim,frontend}:latest` to `host.docker.internal:3000` using the host Docker socket (no DinD), and trusts the self-signed registry CA via injected secrets (`REGISTRY_*`, `CHECKOUT_*`).
- **Cluster bring-up (Terragrunt)**: `make local kind 300 apply` uses the kind provider to create a Docker-backed cluster with NodePorts pre-opened for Argo CD, Hubble, Gitea, and Azure-auth ports (`stages/100-kind.tfvars`/`300-*.tfvars`). Subsequent stages install Cilium (`stages/200-cilium.tfvars`), Hubble (`300-hubble.tfvars`), namespaces + Argo CD (`400-argocd.tfvars`), optional policies (`800-policies.tfvars`), and finally enable the Azure auth sim (`900-azure-auth-sim.tfvars`). Defaults assume an external Gitea (`use_external_gitea = true`); in-cluster Gitea is disabled unless toggled.
- **Workload deployment**: Argo CD tracks the `policies` repo and applies `apps/azure-auth-sim.yaml`, which points to `ssh://gitea-admin@host.docker.internal:30022/gitea-admin/policies.git` at `apps/azure-auth-sim/`. The kustomize set (`apps/azure-auth-sim/*`) deploys Keycloak, OAuth2 Proxy, APIM simulator, FastAPI backend, and protected React frontend using registry images `host.docker.internal:3000/gitea-admin/azure-auth-sim-*`. Terraform creates `gitea-registry-creds` in the `azure-auth-sim` namespace so the pulls succeed. NGINX Gateway Fabric (see `apps/nginx-gateway-fabric`) exposes the oauth2-proxy entry via NodePort `30070` (mapped to localhost:3007) while the remaining services remain internal within the cluster.
- **Gateway Fabric**: The `apps/nginx-gateway-fabric` directory installs NGINX Gateway Fabric’s CRDs, controller, GatewayClass (`nginx`), and proxy service so the HTTPRoute in `apps/azure-auth-sim/gateway.yaml` is the sole NodePort surface for inbound traffic.
- **App-of-apps/policies**: The same `policies` repo also carries Cilium/Kyverno manifests; Argo CD Applications are created in `main.tf` (gitea, cilium-policies, kyverno, kyverno-policies, azure-auth-sim). The repo now keeps cluster-wide controls under `cluster-policies/` and each workload under `apps/<name>/`, so per-app policies (e.g., `apps/azure-auth-sim/policies/cilium/cilium-network-policies.yaml`) stay close to the manifests they protect. Azure-auth-sim app is gated by `enable_azure_auth_sim` (off until stage 900).

## Observations vs intent
- Build path already forces linux/amd64 from macOS and avoids DinD, but it relies on a host-runner and the host Docker socket, not an in-cluster runner.
- Deployment manifests come from the `policies` repo; the separate `azure-auth-sim` repo exists solely for image build sources and the CI workflow.
- Stage comments in `stages/*.tfvars` are legacy (numbers in comments don’t always match filenames); the Makefile sequence under `Usage` is the source of truth.
- External Gitea is assumed; switching to in-cluster Gitea would require toggling `use_external_gitea` and re-seeding via Terraform rather than the stage scripts.
 - Gateway listeners default to `hostname: localhost` for local kind. For AKS or other clusters, override this host (and matching OAuth2/SPA URLs) via a small kustomize patch to `apps/azure-auth-sim/gateway.yaml` and the sidecar manifest, or use a `/etc/hosts` entry (e.g., `127.0.0.1 azure-auth.local`).
 - Policy hand-off: Kyverno now creates namespace-scoped default-deny NetworkPolicies for any namespace labeled `kyverno.io/isolate=true`, while Cilium policies own the explicit allow-list chain (`nginx-gateway -> oauth2-proxy -> frontend -> APIM -> backend`) and egress to control-plane/DNS/Cloudflare.

### Hostname overrides

- Local default: `localhost:3007` (kind NodePort `30070` mapped to host `3007`). Works in normal and private browsing without external DNS.
- Optional local vanity host: add `/etc/hosts` entry `127.0.0.1 azure-auth.local` and set Gateway/OAuth2/SPA URLs to `http://azure-auth.local:3007`.
- For AKS/ingress IP/DNS: create a kustomize patch that sets `spec.listeners[0].hostname` in `apps/azure-auth-sim/gateway.yaml` (and the sidecar overlay, if used) plus update the OAuth2 Proxy args (`--oidc-issuer-url`, `--redirect-url`, `--login-url`) and SPA env vars (`VITE_API_URL`, `VITE_OIDC_AUTHORITY`, `VITE_OIDC_REDIRECT_URI`) to the chosen host.

## Verification plan (next steps)
- Run stages in order: `make local kind 100`, `make local kind 200` (confirm Action succeeded and images exist in `host.docker.internal:3000/v2/gitea-admin/...`), then `make local kind 300/400/500/600/800 apply AUTO_APPROVE=1`, and `make local kind 900 apply AUTO_APPROVE=1`.
- After stage 900: check Argo CD app status (`kubectl -n argocd get applications`), ensure registry secret `gitea-registry-creds` exists in `azure-auth-sim`, and hit the gateway entry (`http://localhost:3007`) to confirm the OAuth2 proxy/front end flow (port-forward `svc/<name>` if you need to reach Keycloak, APIM, or the API directly).

## Sidecar Pattern (Alternative Deployment)

### Overview

The default deployment uses 5 separate pods. An alternative **sidecar pattern** combines oauth2-proxy and frontend into a single pod, reducing to 4 pods while maintaining compose compatibility.

```
Default (5 pods):                          Sidecar (4 pods):
+-----------+   +----------+               +---------------------------+
| oauth2    | > | frontend |               | oauth2-proxy | frontend   |
| proxy     |   |          |               | (sidecar)    | (main)     |
+-----------+   +----------+               +---------------------------+
     |               |                              |
     v               v                              v
+----------+   +----------+   +---------+  +----------+   +---------+
| keycloak |   |   apim   |   | backend |  | keycloak |   |  apim   | > backend
+----------+   +----------+   +---------+  +----------+   +---------+
```

### Key Differences

| Aspect | Separate Pods (default) | Sidecar Pattern |
|--------|------------------------|-----------------|
| Pod count | 5 | 4 |
| oauth2-proxy upstream | Service DNS (`frontend-react-...svc.cluster.local`) | `localhost:80` |
| Frontend accessibility | ClusterIP service | localhost only (within pod) |
| Scaling | Independent | Coupled (1:1) |
| Compose compatibility | Direct mapping | Same images, different orchestration |

### Usage

```bash
# Default pattern (5 pods)
kubectl apply -k apps/azure-auth-sim/

# Sidecar pattern (4 pods)
kubectl apply -k apps/azure-auth-sim/overlays/sidecar/
```

### ArgoCD Configuration

To use the sidecar pattern with ArgoCD, update the Application path:

```yaml
# Default
spec:
  source:
    path: apps/azure-auth-sim

# Sidecar
spec:
  source:
    path: apps/azure-auth-sim/overlays/sidecar
```

### Files

- `overlays/sidecar/combined-sidecar-manifests.yaml` - All resources in a single file
- `overlays/sidecar/kustomization.yaml` - Kustomize overlay configuration

### When to Use

**Use sidecar when:**
- You want tighter coupling between auth and frontend
- Debugging auth issues (logs in same pod)
- Simulating Azure App Service with Easy Auth (single deployment unit)

**Use separate pods when:**
- You need independent scaling
- You want to reuse oauth2-proxy for multiple upstreams
- Testing oauth2-proxy configuration changes independently

### Compose Compatibility

The same container images work in both environments:
- **Compose** (`subnet-calculator/compose.yml`): 5 services as separate containers
- **Kubernetes default**: 5 pods (matches compose)
- **Kubernetes sidecar**: 4 pods (oauth2-proxy + frontend combined)

The sidecar pattern changes orchestration only - no image changes needed.
