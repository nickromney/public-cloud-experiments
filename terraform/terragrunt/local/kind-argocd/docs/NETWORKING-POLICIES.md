# Networking, Cilium, and Kyverno Policy Guide (local/kind-argocd)

This document explains how networking and network security are implemented in the local `kind-argocd` cluster, with a focus on:

1. How Cilium works in this cluster
2. Why we keep kube-proxy and avoid “full kube-proxy replacement” for this setup
3. How Cilium policies are structured in this repo
4. How Kyverno policies are structured in this repo
5. How to extend policies safely for new services
6. Migration considerations (kind -> bare metal / AKS / EKS / GKE)

The design goal is a “default-deny + explicit allow-list” posture while keeping the cluster portable and easy to debug.

## High-level architecture

In this repo, the local kind cluster runs:

- **kind** nodes (Docker) with a single control-plane and multiple workers
- **Cilium** as the CNI (and network policy enforcement)
- **kube-proxy** enabled (iptables mode)
- **NGINX Gateway Fabric** as the Gateway API implementation
- **Argo CD** to reconcile everything from the local Gitea repos
- **Kyverno** to generate baseline default-deny `NetworkPolicy` resources

### Key data paths

#### External traffic (developer laptop -> services)

1. Your host connects to `127.0.0.1:<hostPort>` (for example `443`).
2. kind maps that host port to a NodePort on the control-plane container.
3. The NodePort routes traffic to the **NGINX Gateway dataplane** Service in `azure-auth-gateway`.
4. The dataplane terminates TLS and routes requests to internal services based on HTTPRoutes.

#### Control plane to dataplane (NGINX Gateway Fabric)

NGINX Gateway Fabric uses an agent in each dataplane pod which connects “up” to the controller:

- Dataplane pod (`azure-auth-gateway-nginx`, `apim-gateway-nginx`) -> Service `nginx-gateway.nginx-gateway.svc:443`
- The Service targetPort is `8443` on the controller pod

This connection is required for the dataplane pod to become Ready.

## How Cilium works in this cluster

### What Cilium is doing for us

In this cluster, Cilium provides:

- Pod networking (CNI)
- Network policy enforcement:
  - Kubernetes `NetworkPolicy`
  - Cilium `CiliumNetworkPolicy` (CNP) and `CiliumClusterwideNetworkPolicy` (CCNP)
- Optional features (currently configured but mostly disabled for stability):
  - Hubble observability
  - WireGuard (disabled by default)
  - mesh-auth (disabled by default)

### Relevant local configuration

The kind config keeps kube-proxy enabled:

```yaml
# terraform/terragrunt/local/kind-argocd/kind-config.yaml
networking:
  disableDefaultCNI: true
  kubeProxyMode: "iptables"
```

Cilium is installed via Terraform/Helm with (key bits):

```hcl
# terraform/terragrunt/local/kind-argocd/main.tf
cilium_values_base = {
  kubeProxyReplacement  = false
  routingMode           = "native"
  autoDirectNodeRoutes  = true
  ipv4NativeRoutingCIDR = "10.244.0.0/16"
  ipam = { mode = "kubernetes" }
}
```

Notes:

- `disableDefaultCNI: true` means kind does not install a CNI; Cilium must come up before pods can communicate.
- `ipam.mode = kubernetes` means Cilium uses Kubernetes-assigned PodCIDRs.
- `routingMode = native` and `autoDirectNodeRoutes = true` are commonly used for non-encapsulated routing in simple clusters.

### Service routing and why it matters for policy

With kube-proxy enabled, Service traffic is typically:

1. Pod sends traffic to a **ClusterIP** (virtual IP)
2. kube-proxy applies iptables rules (DNAT) to a real backend endpoint (pod IP + targetPort)

This has a practical implication:

- Your **policy must allow the post-DNAT destination** (often `podIP:targetPort`), not just the Service port.

This shows up most clearly with NGINX Gateway Fabric:

- Service: `nginx-gateway.nginx-gateway.svc:443`
- Target: controller pod on `:8443`

If the dataplane pod can’t connect to `podIP:8443`, the readiness probe will fail and the gateway won’t serve external traffic.

## Why we keep kube-proxy enabled (no “full KPR” here)

### Terminology

- **kube-proxy replacement (KPR)** means Cilium implements Kubernetes Services in eBPF rather than relying on kube-proxy iptables rules.
- “Full KPR” generally means:
  - kind config has `kubeProxyMode: "none"` (no kube-proxy)
  - Cilium has `kubeProxyReplacement: true`

### Decision: keep kube-proxy for this local cluster

We keep kube-proxy enabled and set `kubeProxyReplacement = false` for this cluster because:

1. **Portability**: kind + Docker networking is not representative of bare metal, and KPR-specific issues can be hard to distinguish from kind quirks.
2. **Debuggability**: kube-proxy + iptables is widely understood and has predictable behavior.
3. **Avoid hybrid misconfiguration**: the most failure-prone state is kube-proxy running while Cilium also tries to replace it.
4. **Local development constraints**: we rely heavily on NodePort + extraPortMappings, and kube-proxy is the simplest consistent baseline.

### Practical policy consequence

When kube-proxy is enabled, policies that look like “allow to service X on port Y” often need to be expressed as:

- “allow to endpoints backing service X on targetPort Z”

In this repo, the gateway dataplane egress to the NGINX Gateway Fabric controller is intentionally written this way.

## How Cilium policies are constructed in this repo

### Where policies live

Cluster-wide policies (applied by Argo CD):

- `terraform/terragrunt/local/kind-argocd/cluster-policies/cilium/`
  - `dev-uat-isolation.yaml` (CCNP denies cross-env)
  - `azure-auth-nginx-gateway-ingress.yaml` (control-plane ingress)

App-specific policies (applied by Argo CD):

- `terraform/terragrunt/local/kind-argocd/apps/**/policies/cilium/`
  - `apps/azure-auth-sim/base/policies/cilium/cilium-network-policies.yaml`
  - `apps/azure-auth-gateway/policies/cilium/cilium-network-policies.yaml`
  - `apps/azure-entraid-sim/policies/cilium/cilium-network-policies.yaml`
  - `apps/azure-apim-sim/policies/cilium/cilium-network-policies.yaml`

### Label selector conventions

All Cilium label selectors use the `k8s:` prefix when matching Kubernetes labels. For example:

```yaml
endpointSelector:
  matchLabels:
    "k8s:app.kubernetes.io/name": api-fastapi-keycloak
    "k8s:app.kubernetes.io/component": backend
```

Namespace scoping in selectors uses the synthetic label:

```yaml
"k8s:io.kubernetes.pod.namespace": dev
```

### Default-deny posture (how it is achieved)

The baseline stance is:

- Namespaces labeled `kyverno.io/isolate=true` get a `NetworkPolicy/default-deny` (Kyverno-generated)
- Pods must have explicit allows (usually via Cilium CNPs)
- Dev and UAT are hard-isolated with CCNP denies

### Common policy building blocks

#### Allow DNS

Most workloads need DNS. The common pattern is:

```yaml
egress:
  - toEndpoints:
      - matchLabels:
          "k8s:io.kubernetes.pod.namespace": kube-system
          "k8s:k8s-app": kube-dns
    toPorts:
      - ports:
          - port: "53"
            protocol: UDP
          - port: "53"
            protocol: TCP
```

#### Service-to-service allow-list

Most internal traffic is expressed as `toEndpoints` and `fromEndpoints` rules keyed by:

- `app.kubernetes.io/name`
- `app.kubernetes.io/component`
- and sometimes a namespace label

Example: backend -> azurite

```yaml
egress:
  - toEndpoints:
      - matchLabels:
          "k8s:app.kubernetes.io/name": azurite
          "k8s:app.kubernetes.io/component": storage
    toPorts:
      - ports:
          - port: "10000"
            protocol: TCP
          - port: "10001"
            protocol: TCP
          - port: "10002"
            protocol: TCP
```

#### Clusterwide dev/uat isolation

The strongest safety rail is at the namespace boundary:

```yaml
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: deny-dev-to-uat
spec:
  endpointSelector:
    matchLabels:
      "k8s:io.kubernetes.pod.namespace": dev
  egressDeny:
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": uat
```

This ensures “accidental” connectivity can’t happen even if a namespace policy is too permissive.

### Important nuance: toServices vs toEndpoints

You will see both patterns:

- `toServices`: “allow to this Service”
- `toEndpoints`: “allow to pods with these labels”

In a kube-proxy-enabled cluster, using `toEndpoints` (on the real targetPort) is often the most reliable way to ensure post-DNAT traffic is allowed.

For example, the gateway dataplane must allow the controller pod on `8443`:

```yaml
egress:
  - toEndpoints:
      - matchLabels:
          "k8s:io.kubernetes.pod.namespace": nginx-gateway
          "k8s:app.kubernetes.io/name": nginx-gateway
    toPorts:
      - ports:
          - port: "8443"
            protocol: TCP
```

## How Kyverno policies are constructed in this repo

Kyverno is used to generate and protect a baseline `NetworkPolicy/default-deny` in selected namespaces.

### Where Kyverno policies live

- `terraform/terragrunt/local/kind-argocd/cluster-policies/kyverno/`
  - `namespace-default-deny.yaml`
  - `protect-default-deny.yaml`

### Namespace selection

Any namespace labeled like this will be isolated:

```yaml
metadata:
  labels:
    kyverno.io/isolate: "true"
```

This label is applied to most non-system namespaces in this environment.

### Policy: generate default-deny

Kyverno ClusterPolicy `default-deny-namespaces` generates this in each matching namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

Implications:

- A namespace is isolated by default.
- Connectivity must be opened intentionally using (typically) Cilium CNPs.

### Policy: protect default-deny

Kyverno ClusterPolicy `protect-default-deny-netpol` blocks deleting that default-deny policy in isolated namespaces.

This prevents an “easy escape hatch” that would silently remove isolation.

## Extending policies for new services

This section is a playbook for adding a new component while keeping the current security model.

### General checklist

1. Decide the namespace strategy
   - New namespace (recommended for isolation boundaries)
   - Existing namespace (only if it is truly the same trust domain)
2. Ensure the namespace has `kyverno.io/isolate=true` if you want default-deny
3. Ensure every workload has explicit allow rules:
   - DNS egress
   - Required ingress sources
   - Required egress destinations
4. If traffic must cross `dev` <-> `uat`, reconsider: CCNP denies will block it by design.
5. If the service is behind the NGINX gateway:
   - add a Gateway API route
   - update the gateway dataplane egress allow-list to include the new destination

### Example A: Add an additional frontend hitting the same backend (no frontend-to-frontend)

Goal:

- Frontend A can talk to Backend API
- Frontend B can talk to Backend API
- Frontend A cannot talk to Frontend B
- Frontend B cannot talk to Frontend A

Recommended approach:

1. Give each frontend its own unique `app.kubernetes.io/name`, but keep `app.kubernetes.io/component: frontend`.
2. Ensure both frontends have **only**:
   - ingress from the auth proxy (or gateway)
   - egress to the backend
   - egress to DNS

Example CNP for frontend A:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-frontend-a
spec:
  endpointSelector:
    matchLabels:
      "k8s:app.kubernetes.io/name": frontend-a
      "k8s:app.kubernetes.io/component": frontend
  ingress:
    - fromEndpoints:
        - matchLabels:
            "k8s:app.kubernetes.io/name": oauth2-proxy-frontend
            "k8s:app.kubernetes.io/component": auth-proxy
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:app.kubernetes.io/name": api-fastapi-keycloak
            "k8s:app.kubernetes.io/component": backend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": kube-system
            "k8s:k8s-app": kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

Repeat for frontend B, changing only the `endpointSelector` and policy name.

Why this blocks frontend-to-frontend:

- There is no egress rule from frontend A to pods matching frontend B labels.
- There is no ingress rule allowing frontend A to reach frontend B.
- With default-deny, “not explicitly allowed” means “blocked.”

### Example B: Add a Service Bus emulator (containerized) that must interact with Azurite

There are two common deployment shapes:

1. **Same namespace, separate pods** (recommended)
   - `azurite` is one workload
   - `servicebus-emulator` is a second workload
2. **Same pod** (sidecar)
   - emulator shares a network namespace with Azurite
   - simpler policies, but tighter coupling

Assuming separate pods, you typically need:

- Backend -> emulator (AMQP/HTTP ports as required)
- Emulator -> Azurite (blob/queue/table endpoints if the emulator persists state there)
- DNS egress for any component that resolves names

Skeleton policy for a Service Bus emulator pod:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-servicebus-emulator
spec:
  endpointSelector:
    matchLabels:
      "k8s:app.kubernetes.io/name": servicebus-emulator
      "k8s:app.kubernetes.io/component": messaging
  ingress:
    - fromEndpoints:
        - matchLabels:
            "k8s:app.kubernetes.io/name": api-fastapi-keycloak
            "k8s:app.kubernetes.io/component": backend
      toPorts:
        - ports:
            - port: "5672"
              protocol: TCP
            - port: "5671"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:app.kubernetes.io/name": azurite
            "k8s:app.kubernetes.io/component": storage
      toPorts:
        - ports:
            - port: "10000"
              protocol: TCP
            - port: "10001"
              protocol: TCP
            - port: "10002"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": kube-system
            "k8s:k8s-app": kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

Important notes:

- The ports above are illustrative (AMQP commonly uses 5671/5672). Use the emulator’s actual Service ports.
- If the emulator and Azurite share the same pod, the emulator does not need network access to Azurite.

### Where to put new policies

- If the policy is specific to one app component, add it under that app’s `apps/<app>/.../policies/cilium/` tree.
- If it is a cluster-wide isolation guardrail, add it under `cluster-policies/cilium/`.

After changes, sync policies to local Gitea and let Argo CD reconcile:

```bash
cd terraform/terragrunt
make local kind gitea-sync GITEA_SYNC_ARGS="--policies"
```

## Migration considerations

This section focuses on what changes (and what to re-validate) when moving away from kind.

### From kind to bare metal

What changes:

- No Docker bridge networking. Node-to-node routing and MTU become “real.”
- You likely need a real LoadBalancer implementation for Gateway API (for example MetalLB or Cilium BGP/LB IPAM).

What to revisit:

- Whether to enable kube-proxy replacement (full KPR) for performance and simplicity.
- Host exposure: replace kind `extraPortMappings` with:
  - `LoadBalancer` Services
  - `NodePort` + external LB
  - or direct routing/BGP depending on environment
- Policy correctness under the new Service implementation.

### From kind to AKS

Constraints and choices:

- AKS can run with Cilium, but the exact model (BYOCNI vs managed) impacts what you can customize.
- Gateway API may integrate with cloud load balancers; you usually stop using NodePort mappings.

Migration checklist:

- Replace local `sslip.io` hostnames with real DNS and certificates.
- Ensure Cilium install mode matches your desired datapath (kube-proxy vs KPR).
- Review any `fromEntities: host` rules; “host” in cloud environments can mean different sources.

### From kind to EKS

Constraints and choices:

- Cilium commonly runs with `ipam: aws-eni` in EKS, which changes pod IP allocation.
- AWS security groups / NACLs may also affect traffic (an additional layer beyond Cilium).

Migration checklist:

- Validate all CIDR assumptions (PodCIDR, service CIDR) are not hard-coded.
- Re-validate any `toFQDNs` usage; ensure DNS policies still permit the required lookups.

### From kind to GKE

Important constraint:

- Many GKE configurations do not allow you to freely install Cilium CRDs and use Cilium-specific policies as your primary mechanism.

Practical implication:

- If you need the Cilium CRDs (`CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`), validate early that your chosen GKE mode supports it.
- Otherwise, plan to translate policy intent into standard Kubernetes `NetworkPolicy`.

### General guidance for all migrations

1. Keep the “trust domains” the same (namespaces, components, and traffic flows).
2. Expect to adjust Service exposure (NodePort vs LoadBalancer) and Gateway API integration.
3. Re-run a full “connectivity matrix” test:
   - gateway -> oauth2-proxy -> frontend -> APIM -> backend
   - backend -> keycloak
   - backend -> azurite
   - gateway dataplane -> nginx-gateway control plane

## Troubleshooting tips

### Symptom: TLS handshake to hostPort 443 fails

Common root cause in this environment:

- NGINX Gateway dataplane pod is not Ready

Checklist:

```bash
kubectl -n azure-auth-gateway get pods
kubectl -n azure-auth-gateway describe pod -l app.kubernetes.io/name=azure-auth-gateway-nginx
kubectl -n azure-auth-gateway logs -l app.kubernetes.io/name=azure-auth-gateway-nginx --tail=200
```

### Symptom: dataplane readiness probe failing on 8081

Likely means the agent can’t connect to the control plane.

Validate:

- The dataplane can reach the controller pod `:8443`
- Cilium policy allows the post-DNAT destination

When in doubt, use Cilium drop monitoring:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system exec <cilium-pod> -- cilium monitor --type drop
```
