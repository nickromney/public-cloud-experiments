apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-fastapi-keycloak
  labels:
    app.kubernetes.io/name: api-fastapi-keycloak
    app.kubernetes.io/component: backend
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
              value: http://localhost:${oauth2_proxy_host_port}/realms/subnet-calculator
            - name: OIDC_AUDIENCE
              value: api-app
            - name: OIDC_JWKS_URI
              value: http://keycloak.${azure_entraid_namespace}.svc.cluster.local:8080/realms/subnet-calculator/protocol/openid-connect/certs
            - name: CORS_ORIGINS
              value: http://localhost:${oauth2_proxy_host_port}
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /api/v1/health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 6
