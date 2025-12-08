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
# Check all pods in namespace
kubectl get pods -n azure-auth-sim

# Check services and NodePorts
kubectl get svc -n azure-auth-sim

# Test endpoints
curl -sI http://localhost:3007 --max-time 5   # OAuth2 Proxy (should redirect/403)
curl -sI http://localhost:8180 --max-time 5   # Keycloak
curl -sI http://localhost:8081 --max-time 5   # API
curl -sI http://localhost:8082 --max-time 5   # APIM Simulator
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

Visit http://localhost:30090/gitea-admin/azure-auth-sim/actions

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
