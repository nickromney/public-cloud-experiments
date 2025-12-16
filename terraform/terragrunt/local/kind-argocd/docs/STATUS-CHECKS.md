# Kind-ArgoCD Status Checks

This document describes how to verify the health of the Kind cluster and its components.

## Quick Status Check

Run the status check script:

```bash
./check-status.sh
```

## Components by Stage

### Stage 100 - Kind Cluster

```bash
# Check Kind cluster is running
docker ps --filter "name=kind-local" --format "table {{.Names}}\t{{.Status}}"

# Check nodes are ready
kubectl get nodes

# Verify port mappings
docker inspect kind-local-control-plane | jq '.[0].NetworkSettings.Ports'
```

### Stage 200 - Cilium CNI

```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Cilium status (from agent)
kubectl exec -n kube-system -l k8s-app=cilium -- cilium status --brief
```

### Stage 300 - Hubble Observability

```bash
# Check Hubble relay
kubectl get pods -n kube-system -l k8s-app=hubble-relay

# Check Hubble UI
kubectl get pods -n kube-system -l k8s-app=hubble-ui
```

### Stage 400 - ArgoCD

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check all ArgoCD applications
kubectl get app -n argocd

# Check app-of-apps sync status
kubectl get app -n argocd app-of-apps -o jsonpath='{.status.sync.status}'
```

### Stage 500 - Gitea

```bash
# Check Gitea pods
kubectl get pods -n gitea

# Test Gitea HTTP access
curl -s http://localhost:30090/api/v1/version

# Set credentials (or export in shell profile)
export GITEA_USER="gitea-admin"
export GITEA_PASSWORD="ChangeMe123!"

# List repositories
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" http://localhost:30090/api/v1/user/repos | jq '.[].name'
```

### Stage 600 - Policies (Cilium/Kyverno)

```bash
# Check Cilium policies
kubectl get ciliumnetworkpolicies -A

# Check Kyverno policies (if enabled)
kubectl get clusterpolicies

# Check policy ArgoCD apps
kubectl get app -n argocd cilium-policies kyverno-policies
```

### Stage 700 - Azure Auth Simulation

```bash
# Check all pods in namespaces
kubectl get pods -n dev
kubectl get pods -n uat
kubectl get pods -n azure-auth-gateway

# Check services and NodePorts
kubectl get svc -n dev
kubectl get svc -n uat
kubectl get svc -n azure-auth-gateway

# Test endpoints (Gateway Fabric exposes the oauth2-proxy/front end only)
curl -skI https://subnetcalc.dev.127.0.0.1.sslip.io/ --max-time 5
curl -skI https://subnetcalc.uat.127.0.0.1.sslip.io/ --max-time 5
# To inspect the backend services directly, port-forward the desired service:
# kubectl -n azure-entraid-sim port-forward svc/keycloak 8080:8080
# kubectl -n azure-apim-sim port-forward svc/apim-simulator 8000:8000
# kubectl -n dev port-forward svc/api-fastapi-keycloak 80:80
```

### Gitea Actions Runner

```bash
# Check runner pod
kubectl get pods -n gitea-runner

# Check runner logs
kubectl logs -n gitea-runner -l app.kubernetes.io/name=act-runner --tail=20

# Check runner registration in Gitea (uses GITEA_USER/GITEA_PASSWORD env vars)
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" http://localhost:30090/api/v1/admin/runners | jq '.data[].name'
```

## Development Workflow

### Filtered sync to in-cluster Gitea (Argo paths only)

Use the helper to push only the Argo-consumed paths:

```bash
# Policies only (apps/ + cluster-policies/, default)
terraform/terragrunt/local/kind-argocd/scripts/sync-gitea.sh

# Azure auth sim repo (templates + subnet-calculator sources)
terraform/terragrunt/local/kind-argocd/scripts/sync-gitea.sh --azure-auth-sim

# Both repos
terraform/terragrunt/local/kind-argocd/scripts/sync-gitea.sh --all

# Via Makefile shortcut (runs from terraform/terragrunt)
make local kind gitea-sync                     # defaults to --all (policies + azure-auth-sim)
make local kind gitea-sync GITEA_SYNC_ARGS="--policies --dry-run"
make local kind gitea-sync GITEA_SYNC_ARGS="--azure-auth-sim"
```

## Post-stage-700 cluster smoke test

Run a quick health check (namespaces, Cilium, Argo apps, azure-auth-sim deployments):

```bash
terraform/terragrunt/local/kind-argocd/scripts/check-cluster-health.sh
```

Flags: `--dry-run` to inspect without pushing, `GITEA_BRANCH` to override branch (default `main`), `GITEA_USER/GITEA_PASSWORD` for HTTP auth if your Git credential helper is not already primed, and `GITEA_SYNC_MESSAGE` to set a custom commit message.

### Pushing Code Changes

```bash
# Clone from in-cluster Gitea (will prompt for credentials)
cd /tmp
git clone http://localhost:30090/gitea-admin/azure-auth-sim.git
# Username: gitea-admin
# Password: ChangeMe123!

# Or use credential helper to avoid prompts
git config --global credential.helper store
git clone http://localhost:30090/gitea-admin/azure-auth-sim.git

# Make changes (or copy from local project)
cp -r ~/path/to/subnet-calculator/api-apim-simulator/* azure-auth-sim/api-apim-simulator/

# Commit and push
cd azure-auth-sim
git add . && git commit -m "Update API" && git push

# Watch build logs
kubectl logs -n gitea-runner -l app.kubernetes.io/name=act-runner -f

# Restart deployment to pull new image
kubectl rollout restart deployment/apim-simulator -n azure-auth-sim
```

### Checking Build Status in Gitea

Visit <http://localhost:30090/gitea-admin/azure-auth-sim/actions>

## Troubleshooting

### ArgoCD App Not Syncing

```bash
# Force refresh
kubectl patch app <app-name> -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Check sync status and message
kubectl get app -n argocd <app-name> -o jsonpath='{.status.conditions[*].message}'
```

### Cilium Policy Blocking Traffic

```bash
# Check policy verdict
kubectl exec -n kube-system -l k8s-app=cilium -- \
  cilium monitor --type policy-verdict -n azure-auth-sim

# List endpoints and their policy status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium endpoint list
```

### Images Not Pulling

```bash
# Check image pull secrets exist
kubectl get secret -n azure-auth-sim gitea-registry-creds

# Check pod events
kubectl describe pod -n azure-auth-sim <pod-name>

# Verify image exists in registry
curl -s http://localhost:30090/v2/_catalog
```
