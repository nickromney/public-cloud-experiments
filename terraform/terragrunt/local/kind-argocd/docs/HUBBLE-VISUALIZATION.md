# Hubble UI Visualization Guide

This document explains how to visualize the multi-namespace Azure auth simulation traffic flows using Hubble UI.

## Accessing Hubble UI

Hubble UI is available on NodePort 31235:

```
http://localhost:31235
```

## Namespaces to Observe

Select these namespaces from the dropdown to see the cross-namespace traffic:

- `azure-auth-sim` - AKS workloads (frontend, API, gateway)
- `azure-entraid-sim` - Keycloak (simulates Azure Entra ID)
- `azure-apim-sim` - APIM Simulator (simulates Azure APIM)

## Generating Traffic

To populate the visualization, generate some traffic:

```bash
# Via curl
curl -s http://localhost:3007/realms/subnet-calculator/.well-known/openid-configuration
curl -s http://localhost:3007/apim/api/v1/health
curl -s http://localhost:3007/

# Or simply open http://localhost:3007 in a browser to trigger the full OAuth flow
```

## Expected Traffic Flow Diagram

```
                    ┌─────────────────────────┐
                    │     nginx-gateway       │
                    │   (control plane)       │
                    └───────────┬─────────────┘
                                │
┌───────────────────────────────┼───────────────────────────────┐
│ azure-auth-sim                │                               │
│                               ▼                               │
│    ┌──────────────────────────────────────────┐              │
│    │   azure-auth-gateway-nginx (data plane)  │              │
│    └─────┬────────────────┬───────────────┬───┘              │
│          │                │               │                   │
│          ▼                │               │                   │
│  ┌───────────────┐        │               │                   │
│  │ frontend +    │        │               │                   │
│  │ oauth2-proxy  │────────┼───────────────┼──────────────────┼──► keycloak
│  └───────────────┘        │               │                   │   (azure-entraid-sim)
│                           │               │                   │
│  ┌───────────────┐        │               │                   │
│  │ api-fastapi   │◄───────┼───────────────┼──────────────────┼─── apim-simulator
│  └───────────────┘        │               │                   │   (azure-apim-sim)
│          │                │               │                   │
│          └────────────────┼───────────────┼──────────────────┼──► keycloak (JWKS)
└───────────────────────────┼───────────────┼───────────────────┘
                            │               │
                            ▼               ▼
                    ┌───────────────┐ ┌─────────────────┐
                    │   keycloak    │ │ apim-simulator  │
                    │ (entraid-sim) │ │  (apim-sim)     │
                    └───────────────┘ └─────────────────┘
```

## Cross-Namespace Traffic Flows

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| `azure-auth-gateway-nginx` | `keycloak` (azure-entraid-sim) | 8080 | Keycloak UI/API routing |
| `azure-auth-gateway-nginx` | `apim-simulator` (azure-apim-sim) | 8000 | APIM endpoint routing |
| `azure-auth-gateway-nginx` | `frontend-with-oauth-sidecar` (azure-auth-sim) | 4180 | Frontend via OAuth2 Proxy |
| `frontend-with-oauth-sidecar` | `keycloak` (azure-entraid-sim) | 8080 | OIDC authentication |
| `apim-simulator` | `api-fastapi-keycloak` (azure-auth-sim) | 80 | Backend API calls |
| `api-fastapi-keycloak` | `keycloak` (azure-entraid-sim) | 8080 | JWKS token validation |

## What This Simulates

This multi-namespace architecture simulates a real Azure production topology:

| Namespace | Simulates | Real Azure Service |
|-----------|-----------|-------------------|
| `azure-auth-sim` | AKS workloads | Azure Kubernetes Service |
| `azure-entraid-sim` | External identity provider | Azure Entra ID (AAD) |
| `azure-apim-sim` | API gateway with private endpoint | Azure API Management |

## Cilium Network Policies

The cross-namespace traffic is controlled by these Cilium policies:

- `azure-auth-gateway-egress` - Allows gateway to reach all backends
- `azure-auth-sidecar-policy` - Frontend/OAuth2-Proxy egress to Keycloak and APIM
- `azure-auth-api-sidecar` - API ingress from APIM, egress to Keycloak
- Namespace-specific policies in `azure-entraid-sim` and `azure-apim-sim`

## Troubleshooting

If traffic is being dropped, check:

1. Cilium policy status:

   ```bash
   kubectl get ciliumnetworkpolicy -A
   ```

2. Hubble flow logs:

   ```bash
   kubectl exec -n kube-system -it ds/cilium -- hubble observe --namespace azure-auth-sim
   ```

3. Specific dropped flows:

   ```bash
   kubectl exec -n kube-system -it ds/cilium -- hubble observe --verdict DROPPED
   ```
