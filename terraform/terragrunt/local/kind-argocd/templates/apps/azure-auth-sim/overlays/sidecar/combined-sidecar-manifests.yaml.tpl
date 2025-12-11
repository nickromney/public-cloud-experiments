# Combined Sidecar Manifests for Azure Auth Simulation
#
# Multi-namespace architecture (sidecar variant):
#   - azure-auth-sim: Frontend + OAuth2-Proxy (sidecar), Backend API (simulates AKS workloads)
#   - azure-entraid-sim: Keycloak (simulates Azure Entra ID) - deployed separately
#   - azure-apim-sim: APIM Simulator (simulates Azure APIM) - deployed separately
#
# This manifest only deploys azure-auth-sim resources.
# Keycloak and APIM are in their respective namespaces.
#
# Usage:
#   kubectl apply -f combined-sidecar-manifests.yaml
#
# Result: 2 pods in azure-auth-sim
#   - api-fastapi-keycloak
#   - frontend-with-oauth-sidecar (oauth2-proxy + frontend)
#
# Ports:
#   - 3007 (30070): Gateway front door (routes to OAuth2 Proxy + APIs)
#
---
apiVersion: v1
kind: Namespace
metadata:
  name: azure-auth-sim
  labels:
    app.kubernetes.io/part-of: azure-auth-sim
    app.kubernetes.io/variant: sidecar
---
apiVersion: v1
kind: Secret
metadata:
  name: azure-auth-secrets
  namespace: azure-auth-sim
type: Opaque
stringData:
  # Demo-only secrets for the local azure auth simulation workload
  oauth2-proxy-cookie-secret: OQINaROshtE9TcZkNAm-5Zs2pZWWyqhBcfyqGMC5H0A=
  oauth2-proxy-client-secret: frontend-secret
---
# FastAPI Backend - API Server
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-fastapi-keycloak
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: api-fastapi-keycloak
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: azure-auth-sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: api-fastapi-keycloak
      app.kubernetes.io/component: backend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: api-fastapi-keycloak
        app.kubernetes.io/component: backend
    spec:
      imagePullSecrets:
        - name: gitea-registry-creds
      containers:
        - name: api-fastapi-keycloak
          image: ${registry_host}/${gitea_admin_username}/azure-auth-sim-api:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: AUTH_METHOD
              value: oidc
            - name: OIDC_ISSUER
              value: http://localhost:3007/realms/subnet-calculator
            - name: OIDC_AUDIENCE
              value: api-app
            # Cross-namespace reference to Keycloak in azure-entraid-sim
            - name: OIDC_JWKS_URI
              value: http://keycloak.${azure_entraid_namespace}.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
            - name: CORS_ORIGINS
              value: http://localhost:3007
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: api-fastapi-keycloak
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: api-fastapi-keycloak
    app.kubernetes.io/component: backend
spec:
  selector:
    app.kubernetes.io/name: api-fastapi-keycloak
    app.kubernetes.io/component: backend
  ports:
    - name: http
      port: 80
      targetPort: http
---
# SIDECAR DEPLOYMENT: OAuth2 Proxy + Frontend in one Pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-with-oauth-sidecar
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: frontend-with-oauth-sidecar
    app.kubernetes.io/component: frontend-protected
    app.kubernetes.io/part-of: azure-auth-sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: frontend-with-oauth-sidecar
      app.kubernetes.io/component: frontend-protected
  template:
    metadata:
      labels:
        app.kubernetes.io/name: frontend-with-oauth-sidecar
        app.kubernetes.io/component: frontend-protected
      annotations:
        # Bump to force rollout when build inputs change
        app.kubernetes.io/version: "rev-3007-3-multi-ns"
    spec:
      imagePullSecrets:
        - name: gitea-registry-creds
      containers:
        # Sidecar container - OAuth2 Proxy (entry point)
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.13.0
          imagePullPolicy: IfNotPresent
          args:
            # OIDC Provider (Keycloak in azure-entraid-sim namespace)
            - --provider=oidc
            - --oidc-issuer-url=http://localhost:3007/realms/subnet-calculator
            - --client-id=frontend-app
            - --redirect-url=http://localhost:3007/oauth2/callback
            - --code-challenge-method=S256
            # Skip discovery - pin endpoints to Keycloak service (cross-namespace)
            - --skip-oidc-discovery=true
            - --login-url=http://localhost:3007/realms/subnet-calculator/protocol/openid-connect/auth
            - --redeem-url=http://keycloak.${azure_entraid_namespace}.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/token
            - --oidc-jwks-url=http://keycloak.${azure_entraid_namespace}.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
            - --validate-url=http://keycloak.${azure_entraid_namespace}.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/userinfo
            # SIDECAR PATTERN: upstream is localhost (same pod)
            - --upstream=http://localhost:80
            # Listen address
            - --http-address=0.0.0.0:4180
            # Cookie configuration
            - --cookie-secure=false
            - --cookie-httponly=true
            - --cookie-expire=4h
            - --cookie-refresh=1h
            - --cookie-name=_oauth2_proxy
            - --email-domain=*
            # Scopes and headers
            - --scope=openid user_impersonation
            - --pass-authorization-header=true
            - --pass-access-token=true
            - --pass-user-headers=true
            - --set-authorization-header=true
            - --set-xauthrequest=true
            - --standard-logging=true
            - --auth-logging=true
            - --request-logging=true
          env:
            - name: OAUTH2_PROXY_COOKIE_SECRET
              valueFrom:
                secretKeyRef:
                  name: azure-auth-secrets
                  key: oauth2-proxy-cookie-secret
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: azure-auth-secrets
                  key: oauth2-proxy-client-secret
          ports:
            - name: http
              containerPort: 4180
          readinessProbe:
            httpGet:
              path: /ping
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /ping
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
        # Main container - Frontend (only accessible via localhost)
        - name: frontend
          image: ${registry_host}/${gitea_admin_username}/azure-auth-sim-frontend:latest
          imagePullPolicy: IfNotPresent
          env:
            # Cross-namespace reference to APIM in azure-apim-sim
            - name: VITE_API_URL
              value: http://localhost:3007/apim
            - name: VITE_API_PROXY_ENABLED
              value: "false"
            - name: VITE_AUTH_METHOD
              value: oidc
            - name: VITE_OIDC_AUTHORITY
              value: http://localhost:3007/realms/subnet-calculator
            - name: VITE_OIDC_CLIENT_ID
              value: frontend-app
            - name: VITE_OIDC_REDIRECT_URI
              value: http://localhost:3007
            - name: VITE_OIDC_AUTO_LOGIN
              value: "true"
          ports:
            - name: frontend
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: frontend
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          resources:
            requests:
              memory: "32Mi"
              cpu: "25m"
            limits:
              memory: "64Mi"
              cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-with-oauth-sidecar
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: frontend-with-oauth-sidecar
    app.kubernetes.io/component: frontend-protected
spec:
  selector:
    app.kubernetes.io/name: frontend-with-oauth-sidecar
    app.kubernetes.io/component: frontend-protected
  ports:
    - name: http
      port: 4180
      targetPort: http
---
# Gateway resources for the sidecar deployment
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: azure-auth-gateway
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: azure-auth-gateway
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: localhost
      allowedRoutes:
        namespaces:
          from: All
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: azure-auth-gateway-route
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: azure-auth-gateway-route
spec:
  parentRefs:
    - name: azure-auth-gateway
  rules:
    # Keycloak routes - cross-namespace to azure-entraid-sim
    # ReferenceGrant in azure-entraid-sim allows this
    - matches:
        - path:
            type: PathPrefix
            value: /realms
        - path:
            type: PathPrefix
            value: /resources
      backendRefs:
        - name: keycloak
          namespace: ${azure_entraid_namespace}
          port: 8080
          kind: Service
    # APIM routes - cross-namespace to azure-apim-sim
    # ReferenceGrant in azure-apim-sim allows this
    - matches:
        - path:
            type: PathPrefix
            value: /apim
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /
      backendRefs:
        - name: apim-simulator
          namespace: ${azure_apim_namespace}
          port: 8000
          kind: Service
    # Frontend route - same namespace
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend-with-oauth-sidecar
          port: 4180
          kind: Service
---
# Cilium Network Policies for sidecar deployment with cross-namespace traffic
#
# Cross-namespace architecture:
# - Keycloak is in azure-entraid-sim namespace (simulates Azure Entra ID)
# - APIM Simulator is in azure-apim-sim namespace (simulates Azure APIM)
# - Frontend and Backend API remain in this namespace (simulates AKS workloads)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-sidecar-policy
  namespace: azure-auth-sim
spec:
  description: Frontend+OAuth2-Proxy sidecar pod policy with cross-namespace egress
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: frontend-with-oauth-sidecar
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: nginx-gateway
      toPorts:
        - ports:
            - port: "4180"
              protocol: TCP
  egress:
    # Cross-namespace egress to Keycloak in azure-entraid-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            "k8s:io.kubernetes.pod.namespace": ${azure_entraid_namespace}
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    # Cross-namespace egress to APIM in azure-apim-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
            "k8s:io.kubernetes.pod.namespace": ${azure_apim_namespace}
      toPorts:
        - ports:
            - port: "8000"
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
    - toEntities:
        - kube-apiserver
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-gateway-ingress
  namespace: azure-auth-sim
spec:
  description: Allow host -> azure-auth gateway data plane on NodePort (front door).
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: azure-auth-gateway-nginx
  ingress:
    - fromEntities:
        - host
        - remote-node
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
---
# Gateway egress policy - allows gateway to reach all backends
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-gateway-egress
  namespace: azure-auth-sim
spec:
  description: Allow gateway data plane to reach backend services (cross-namespace).
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: azure-auth-gateway-nginx
  egress:
    # Local backend - frontend with oauth sidecar
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: frontend-with-oauth-sidecar
            "k8s:io.kubernetes.pod.namespace": azure-auth-sim
      toPorts:
        - ports:
            - port: "4180"
              protocol: TCP
    # Cross-namespace egress to Keycloak in azure-entraid-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            "k8s:io.kubernetes.pod.namespace": ${azure_entraid_namespace}
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    # Cross-namespace egress to APIM in azure-apim-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
            "k8s:io.kubernetes.pod.namespace": ${azure_apim_namespace}
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    # DNS resolution
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
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-api-sidecar
  namespace: azure-auth-sim
spec:
  description: Backend API policy with cross-namespace ingress from APIM
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: api-fastapi-keycloak
  ingress:
    # Cross-namespace ingress from APIM in azure-apim-sim
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
            "k8s:io.kubernetes.pod.namespace": ${azure_apim_namespace}
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
  egress:
    # Cross-namespace egress to Keycloak in azure-entraid-sim for token validation
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            "k8s:io.kubernetes.pod.namespace": ${azure_entraid_namespace}
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    # Egress to Cloudflare for health check endpoint
    - toFQDNs:
        - matchName: www.cloudflare.com
        - matchName: cloudflare.com
      toPorts:
        - ports:
            - port: "443"
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
---
# Policy for NGINX Gateway to route to cross-namespace backends
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-nginx-gateway-sidecar
  namespace: nginx-gateway
spec:
  description: Allow NGINX Gateway to forward traffic to backend services across namespaces (sidecar variant).
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: nginx-gateway
  egress:
    # Frontend in azure-auth-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: frontend-with-oauth-sidecar
            "k8s:io.kubernetes.pod.namespace": azure-auth-sim
      toPorts:
        - ports:
            - port: "4180"
              protocol: TCP
    # Cross-namespace egress to Keycloak in azure-entraid-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
            "k8s:io.kubernetes.pod.namespace": ${azure_entraid_namespace}
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    # Cross-namespace egress to APIM in azure-apim-sim
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
            "k8s:io.kubernetes.pod.namespace": ${azure_apim_namespace}
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
    - toEntities:
        - kube-apiserver
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
