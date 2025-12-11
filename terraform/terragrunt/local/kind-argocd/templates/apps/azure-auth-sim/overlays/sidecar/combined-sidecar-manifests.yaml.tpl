# Combined Sidecar Manifests for Azure Auth Simulation
#
# This is a standalone manifest that deploys the sidecar variant:
#   - oauth2-proxy + frontend in one pod (true sidecar pattern)
#   - keycloak, api, apim-simulator as separate pods
#
# Usage:
#   kubectl apply -f combined-sidecar-manifests.yaml
#
# Result: 4 pods instead of 5
#   - keycloak
#   - api-fastapi-keycloak
#   - apim-simulator
#   - frontend-with-oauth-sidecar (oauth2-proxy + frontend)
#
# Ports:
#   - 3007 (30070): Gateway front door (routes to OAuth2 Proxy + APIs; Keycloak/APIM/API stay internal)
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
  apim-subscription-key: stack12-demo-key
  oauth2-proxy-cookie-secret: OQINaROshtE9TcZkNAm-5Zs2pZWWyqhBcfyqGMC5H0A=
  oauth2-proxy-client-secret: frontend-secret
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-realm-export
  namespace: azure-auth-sim
data:
  realm-export.json: |-
    {
      "realm": "subnet-calculator",
      "enabled": true,
      "displayName": "Subnet Calculator",
      "displayNameHtml": "<div>Subnet Calculator</div>",
      "sslRequired": "none",
      "registrationAllowed": false,
      "loginWithEmailAllowed": true,
      "duplicateEmailsAllowed": false,
      "resetPasswordAllowed": false,
      "editUsernameAllowed": false,
      "bruteForceProtected": true,
      "accessTokenLifespan": 1800,
      "ssoSessionIdleTimeout": 1800,
      "ssoSessionMaxLifespan": 36000,
      "offlineSessionIdleTimeout": 2592000,
      "accessCodeLifespan": 60,
      "accessCodeLifespanUserAction": 300,
      "accessCodeLifespanLogin": 1800,
      "clients": [
        {
          "clientId": "frontend-app",
          "name": "React Frontend",
          "description": "React SPA frontend. OAuth2 Proxy handles server-side auth; oidc-client-ts manages browser token flow.",
          "enabled": true,
          "publicClient": true,
          "protocol": "openid-connect",
          "directAccessGrantsEnabled": false,
          "standardFlowEnabled": true,
          "implicitFlowEnabled": false,
          "attributes": {
            "pkce.code.challenge.method": "S256"
          },
          "redirectUris": [
            "http://localhost:3006/*",
            "http://localhost:3007/*"
          ],
          "webOrigins": [
            "http://localhost:3006",
            "http://localhost:3007"
          ],
          "fullScopeAllowed": true,
          "protocolMappers": [
            {
              "name": "username",
              "protocol": "openid-connect",
              "protocolMapper": "oidc-usermodel-property-mapper",
              "consentRequired": false,
              "config": {
                "userinfo.token.claim": "true",
                "user.attribute": "username",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "preferred_username",
                "jsonType.label": "String"
              }
            },
            {
              "name": "email",
              "protocol": "openid-connect",
              "protocolMapper": "oidc-usermodel-property-mapper",
              "consentRequired": false,
              "config": {
                "userinfo.token.claim": "true",
                "user.attribute": "email",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "email",
                "jsonType.label": "String"
              }
            }
          ]
        },
        {
          "clientId": "api-app",
          "name": "FastAPI Backend",
          "description": "FastAPI backend API",
          "enabled": true,
          "publicClient": false,
          "protocol": "openid-connect",
          "bearerOnly": true,
          "standardFlowEnabled": false,
          "directAccessGrantsEnabled": false,
          "serviceAccountsEnabled": false,
          "fullScopeAllowed": true,
          "attributes": {
            "access.token.lifespan": "1800"
          }
        }
      ],
      "clientScopes": [
        {
          "name": "user_impersonation",
          "description": "Access Subnet Calculator API on behalf of user",
          "protocol": "openid-connect",
          "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "true",
            "consent.screen.text": "Access the Subnet Calculator API"
          },
          "protocolMappers": [
            {
              "name": "audience-mapper",
              "protocol": "openid-connect",
              "protocolMapper": "oidc-audience-mapper",
              "consentRequired": false,
              "config": {
                "included.client.audience": "api-app",
                "id.token.claim": "false",
                "access.token.claim": "true"
              }
            }
          ]
        }
      ],
      "defaultDefaultClientScopes": [
        "profile",
        "email",
        "user_impersonation"
      ],
      "users": [
        {
          "username": "demo",
          "enabled": true,
          "emailVerified": true,
          "firstName": "Demo",
          "lastName": "User",
          "email": "demo@example.com",
          "credentials": [
            {
              "type": "password",
              "value": "password123",
              "temporary": false
            }
          ],
          "realmRoles": [
            "user"
          ]
        },
        {
          "username": "admin",
          "enabled": true,
          "emailVerified": true,
          "firstName": "Admin",
          "lastName": "User",
          "email": "admin@example.com",
          "credentials": [
            {
              "type": "password",
              "value": "securepass",
              "temporary": false
            }
          ],
          "realmRoles": [
            "admin",
            "user"
          ]
        }
      ],
      "roles": {
        "realm": [
          {
            "name": "user",
            "description": "User role"
          },
          {
            "name": "admin",
            "description": "Administrator role"
          }
        ]
      }
    }
---
# Keycloak - Identity Provider
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/component: identity
    app.kubernetes.io/part-of: azure-auth-sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak
      app.kubernetes.io/component: identity
  template:
    metadata:
      labels:
        app.kubernetes.io/name: keycloak
        app.kubernetes.io/component: identity
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:26.4.5
          imagePullPolicy: IfNotPresent
          args:
            - start-dev
            - --import-realm
          env:
            - name: KC_BOOTSTRAP_ADMIN_USERNAME
              value: admin
            - name: KC_BOOTSTRAP_ADMIN_PASSWORD
              value: admin123
            - name: KC_DB
              value: dev-file
            - name: KC_HOSTNAME_STRICT
              value: "false"
            - name: KC_HOSTNAME_STRICT_HTTPS
              value: "false"
            # Configure Keycloak to generate redirect URLs pointing to the NGINX Gateway
            # external endpoint (localhost:3007) rather than the internal service endpoint
            - name: KC_HOSTNAME
              value: "localhost"
            - name: KC_HOSTNAME_PORT
              value: "3007"
            - name: KC_HOSTNAME_URL
              value: "http://localhost:3007"
            - name: KC_HOSTNAME_STRICT_BACKCHANNEL
              value: "false"
            - name: KC_PROXY
              value: "edge"
            - name: KC_HTTP_ENABLED
              value: "true"
            - name: KC_HEALTH_ENABLED
              value: "true"
            - name: KC_METRICS_ENABLED
              value: "true"
          ports:
            - name: http
              containerPort: 8080
            - name: management
              containerPort: 9000
          volumeMounts:
            - name: realm-export
              mountPath: /opt/keycloak/data/import/realm-export.json
              subPath: realm-export.json
          readinessProbe:
            httpGet:
              path: /health/ready
              port: management
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /health/live
              port: management
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
      volumes:
        - name: realm-export
          configMap:
            name: keycloak-realm-export
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/component: identity
spec:
  selector:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/component: identity
  ports:
    - name: http
      port: 8080
      targetPort: http
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
          imagePullPolicy: Always
          env:
            - name: AUTH_METHOD
              value: oidc
            - name: OIDC_ISSUER
              value: http://localhost:3007/realms/subnet-calculator
            - name: OIDC_AUDIENCE
              value: api-app
            - name: OIDC_JWKS_URI
              value: http://keycloak.azure-auth-sim.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
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
# APIM Simulator - API Gateway
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apim-simulator
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: apim-simulator
    app.kubernetes.io/component: gateway
    app.kubernetes.io/part-of: azure-auth-sim
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: apim-simulator
      app.kubernetes.io/component: gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: apim-simulator
        app.kubernetes.io/component: gateway
    spec:
      imagePullSecrets:
        - name: gitea-registry-creds
      containers:
        - name: apim-simulator
          image: ${registry_host}/${gitea_admin_username}/azure-auth-sim-apim:latest
          imagePullPolicy: Always
          env:
            - name: BACKEND_BASE_URL
              value: http://api-fastapi-keycloak.azure-auth-sim.svc.cluster.local
            - name: OIDC_ISSUER
              value: http://localhost:3007/realms/subnet-calculator
            - name: OIDC_AUDIENCE
              value: api-app
            - name: OIDC_JWKS_URI
              value: http://keycloak.azure-auth-sim.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
            - name: ALLOWED_ORIGINS
              value: http://localhost:3007
            - name: ALLOW_ANONYMOUS
              value: "true"
            - name: APIM_SUBSCRIPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: azure-auth-secrets
                  key: apim-subscription-key
          ports:
            - name: http
              containerPort: 8000
          readinessProbe:
            httpGet:
              path: /apim/health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /apim/health
              port: http
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
---
apiVersion: v1
kind: Service
metadata:
  name: apim-simulator
  namespace: azure-auth-sim
  labels:
    app.kubernetes.io/name: apim-simulator
    app.kubernetes.io/component: gateway
spec:
  selector:
    app.kubernetes.io/name: apim-simulator
    app.kubernetes.io/component: gateway
  ports:
    - name: http
      port: 8000
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
        app.kubernetes.io/version: "rev-3007-2"
    spec:
      imagePullSecrets:
        - name: gitea-registry-creds
      containers:
        # Sidecar container - OAuth2 Proxy (entry point)
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.13.0
          imagePullPolicy: IfNotPresent
          args:
            # OIDC Provider (Keycloak)
            - --provider=oidc
            - --oidc-issuer-url=http://localhost:3007/realms/subnet-calculator
            - --client-id=frontend-app
            - --redirect-url=http://localhost:3007/oauth2/callback
            - --code-challenge-method=S256
            # Skip discovery - pin endpoints to Keycloak service
            - --skip-oidc-discovery=true
            - --login-url=http://localhost:3007/realms/subnet-calculator/protocol/openid-connect/auth
            - --redeem-url=http://keycloak.azure-auth-sim.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/token
            - --oidc-jwks-url=http://keycloak.azure-auth-sim.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
            - --validate-url=http://keycloak.azure-auth-sim.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/userinfo
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
          imagePullPolicy: Always
          env:
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
            - name: VITE_APIM_SUBSCRIPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: azure-auth-secrets
                  key: apim-subscription-key
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
          from: Same
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
    - matches:
        - path:
            type: PathPrefix
            value: /realms
        - path:
            type: PathPrefix
            value: /resources
      backendRefs:
        - name: keycloak
          port: 8080
          kind: Service
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
          port: 8000
          kind: Service
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend-with-oauth-sidecar
          port: 4180
          kind: Service
---
# Network Policy for Sidecar Pod
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-sidecar-policy
  namespace: azure-auth-sim
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: frontend-with-oauth-sidecar
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: azure-auth-gateway-nginx
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": "kube-system"
            "k8s:k8s-app": "kube-dns"
    - toEntities:
        - kube-apiserver
        - host


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
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: azure-auth-apim-sidecar
  namespace: azure-auth-sim
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: apim-simulator
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: frontend-with-oauth-sidecar
        - matchLabels:
            app.kubernetes.io/name: azure-auth-gateway-nginx
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: api-fastapi-keycloak
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": "kube-system"
            "k8s:k8s-app": "kube-dns"
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
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: api-fastapi-keycloak
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
        - matchLabels:
            app.kubernetes.io/name: azure-auth-gateway-nginx
            k8s:io.kubernetes.pod.namespace: azure-auth-sim
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            app.kubernetes.io/name: keycloak
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": "kube-system"
            "k8s:k8s-app": "kube-dns"
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
  name: azure-auth-keycloak-sidecar
  namespace: azure-auth-sim
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: keycloak
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: frontend-with-oauth-sidecar
        - matchLabels:
            app.kubernetes.io/name: apim-simulator
        - matchLabels:
            app.kubernetes.io/name: api-fastapi-keycloak
        - matchLabels:
            app.kubernetes.io/name: azure-auth-gateway-nginx
            k8s:io.kubernetes.pod.namespace: azure-auth-sim
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": "kube-system"
            "k8s:k8s-app": "kube-dns"
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
