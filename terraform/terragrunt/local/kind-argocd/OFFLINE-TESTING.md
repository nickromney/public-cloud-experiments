# Offline Testing Guide

This guide covers working with the kind cluster when you have limited or no internet connectivity.

## How Container Images Work with Kind

Kind clusters run inside Docker/Podman containers. By default, pods pull images from remote registries (Docker Hub, Quay.io, etc.). For offline work, you need to:

1. **Pre-pull/build images** while online
2. **Load images into kind** so they're available inside the cluster

### Image Storage Locations

```
Local machine (podman/docker) --> kind load --> Kind cluster nodes
```

- `podman images` - shows images on your local machine
- `kind load docker-image` - copies images INTO the kind cluster
- Once loaded, pods can use `imagePullPolicy: Never` or `IfNotPresent`

## Preparation (While Online)

### 1. Pull Required Base Images

```bash
# Keycloak (identity provider)
podman pull quay.io/keycloak/keycloak:26.4.5

# OAuth2 Proxy (Easy Auth simulation)
podman pull quay.io/oauth2-proxy/oauth2-proxy:v7.13.0

# ArgoCD images (if not using Helm)
podman pull quay.io/argoproj/argocd:v2.14.11

# Cilium images
podman pull quay.io/cilium/cilium:v1.17.4
podman pull quay.io/cilium/operator-generic:v1.17.4
podman pull quay.io/cilium/hubble-relay:v1.17.4
podman pull quay.io/cilium/hubble-ui:v0.13.1
podman pull quay.io/cilium/hubble-ui-backend:v0.13.1

# Kyverno
podman pull ghcr.io/kyverno/kyverno:v1.13.4
podman pull ghcr.io/kyverno/kyvernopre:v1.13.4
podman pull ghcr.io/kyverno/background-controller:v1.13.4
podman pull ghcr.io/kyverno/cleanup-controller:v1.13.4
podman pull ghcr.io/kyverno/reports-controller:v1.13.4

# Gitea
podman pull gitea/gitea:1.23.8
podman pull docker.io/bitnami/postgresql:16.3.0-debian-12-r23

# Kind node image
podman pull kindest/node:v1.33.1
```

### 2. Build Application Images

```bash
cd /path/to/public-cloud-experiments/subnet-calculator

# Build Stack 12 images
podman-compose build api-fastapi-keycloak
podman-compose build apim-simulator
podman-compose build frontend-react-keycloak-protected

# Verify images exist
podman images | grep subnet-calculator
```

### 3. Save Images to Tar Files (Optional)

For complete offline portability, save images to tar files:

```bash
mkdir -p ~/offline-images

# Save custom images
podman save -o ~/offline-images/api-fastapi-keycloak.tar localhost/subnet-calculator-api-fastapi-keycloak:latest
podman save -o ~/offline-images/apim-simulator.tar localhost/subnet-calculator-apim-simulator:latest
podman save -o ~/offline-images/frontend-react-protected.tar localhost/subnet-calculator-frontend-react-protected:latest

# Save external images
podman save -o ~/offline-images/keycloak.tar quay.io/keycloak/keycloak:26.4.5
podman save -o ~/offline-images/oauth2-proxy.tar quay.io/oauth2-proxy/oauth2-proxy:v7.13.0
```

To restore later:

```bash
podman load -i ~/offline-images/keycloak.tar
```

## Loading Images into Kind

### Method 1: Load from Local Podman/Docker

```bash
# Load a single image
kind load docker-image localhost/subnet-calculator-api-fastapi-keycloak:latest --name kind-local

# Load multiple images
kind load docker-image \
  localhost/subnet-calculator-api-fastapi-keycloak:latest \
  localhost/subnet-calculator-apim-simulator:latest \
  localhost/subnet-calculator-frontend-react-protected:latest \
  quay.io/keycloak/keycloak:26.4.5 \
  quay.io/oauth2-proxy/oauth2-proxy:v7.13.0 \
  --name kind-local
```

### Method 2: Load from Tar Archive

```bash
kind load image-archive ~/offline-images/keycloak.tar --name kind-local
```

### Verify Images in Kind

```bash
# Check images on kind nodes
docker exec -it kind-local-control-plane crictl images
# or with podman
podman exec -it kind-local-control-plane crictl images
```

## Kubernetes Manifest Requirements for Offline

When deploying to kind offline, ensure your manifests use:

```yaml
spec:
  containers:
    - name: my-app
      image: localhost/subnet-calculator-api-fastapi-keycloak:latest
      imagePullPolicy: Never  # or IfNotPresent
```

- `imagePullPolicy: Never` - Only use pre-loaded images, never pull
- `imagePullPolicy: IfNotPresent` - Use local if available, pull if not

## Complete Offline Workflow

### Before Going Offline

```bash
# 1. Ensure cluster is running
kubectl config current-context  # should show kind-kind-local

# 2. Pull all required images
./scripts/pull-offline-images.sh  # (create this script with pulls above)

# 3. Build custom images
cd subnet-calculator
podman-compose build api-fastapi-keycloak apim-simulator frontend-react-keycloak-protected

# 4. Load images into kind
kind load docker-image \
  localhost/subnet-calculator-api-fastapi-keycloak:latest \
  localhost/subnet-calculator-apim-simulator:latest \
  localhost/subnet-calculator-frontend-react-protected:latest \
  quay.io/keycloak/keycloak:26.4.5 \
  quay.io/oauth2-proxy/oauth2-proxy:v7.13.0 \
  --name kind-local

# 5. Verify
podman exec -it kind-local-control-plane crictl images | grep -E "keycloak|oauth2|subnet"
```

### While Offline

```bash
# Cluster operations work fine
kubectl get pods -A
kubectl apply -f manifests/

# ArgoCD UI (if already deployed)
open http://localhost:30080

# Gitea (if already deployed)
open http://localhost:30090

# Hubble UI
open http://localhost:31235
```

### Troubleshooting Offline Issues

**Pod stuck in ImagePullBackOff:**

```bash
# Check the image name
kubectl describe pod <pod-name> -n <namespace>

# Verify image is loaded in kind
podman exec -it kind-local-control-plane crictl images | grep <image-name>

# If missing, load it
kind load docker-image <image:tag> --name kind-local
```

**Helm charts trying to pull images:**

Helm charts may reference images you haven't pre-loaded. Check the chart values:

```bash
helm show values argo/argo-cd | grep -i image
```

Then pull those images before going offline.

## Port Mappings Reference

These ports are exposed from the kind cluster to localhost:

| Service | Port | URL |
|---------|------|-----|
| ArgoCD UI | 30080 | http://localhost:30080 |
| Gitea HTTP | 30090 | http://localhost:30090 |
| Gitea SSH | 30022 | ssh://git@localhost:30022 |
| Hubble UI | 31235 | http://localhost:31235 |
| Stack 12 OAuth2 Proxy entry (via NGINX Gateway Fabric) | 3007 | http://localhost:3007 |

Keycloak, the APIM simulator, and the FastAPI backend remain cluster-internal; port-forward the services when you need to hit them directly (e.g., `kubectl -n azure-auth-sim port-forward svc/keycloak 8080:8080`).

## Notes

- Kind stores images in containerd inside the Docker/Podman container
- Restarting the kind cluster preserves loaded images
- Deleting and recreating the cluster requires reloading all images
- The `kind load` command works with both Docker and Podman backends
