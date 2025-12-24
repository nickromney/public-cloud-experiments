# Grafana fallback plan (replace SigNoz UI with native Keycloak SSO)

## Goal

If SigNoz OSS continues to be brittle behind Keycloak, switch the UI to **Grafana OSS** with **native Keycloak OIDC** (`auth.generic_oauth`), while preserving observability features via Prometheus/Loki/Tempo (or VictoriaMetrics).

## Why Grafana

- SigNoz OSS does **not** provide native OIDC/SAML SSO (Keycloak) in the same way Grafana does.
- Grafana OSS supports Keycloak directly using `auth.generic_oauth`.

## Option A (most standard): kube-prometheus-stack + Loki + Tempo

### 1) Remove/disable SigNoz UI exposure

1. Disable/remove the SigNoz Argo CD Applications (SigNoz and any SigNoz k8s infra app) from the app-of-apps inputs.
2. Remove/disable SigNoz gateway-route resources:
   - `HTTPRoute signoz`
   - SigNoz-specific `oauth2-proxy` and `signoz-auth-proxy` resources
3. (Optional) Remove SigNoz storage (PVCs) if you want a clean uninstall.

### 2) Deploy Prometheus + Grafana

1. Add an Argo CD Application for Helm chart `prometheus-community/kube-prometheus-stack`.
2. Enable Grafana.
3. Expose Grafana via the existing Gateway/HTTPRoute pattern at:
   - `https://grafana.127.0.0.1.sslip.io/`

### 3) Deploy Loki (logs)

1. Deploy Loki (either `grafana/loki` or `grafana/loki-stack`).
2. Deploy a log shipper:
   - Promtail, Grafana Agent, or Grafana Alloy.

### 4) Deploy Tempo (traces)

1. Deploy `grafana/tempo`.
2. Ensure an OTLP receiver is enabled.
3. Ensure workloads send OTLP to an OpenTelemetry Collector that exports:
   - traces → Tempo
   - logs → Loki
   - metrics → Prometheus scrape / remote_write (depending on the stack)

### 5) Configure Keycloak client for Grafana

1. Create Keycloak client `grafana`:
   - Redirect URI: `https://grafana.127.0.0.1.sslip.io/login/generic_oauth`
   - Web origins: `https://grafana.127.0.0.1.sslip.io`
2. Store `client_secret` in a Kubernetes Secret.
3. Configure Grafana `grafana.ini` values:
   - `[auth.generic_oauth] enabled = true`
   - `client_id`, `client_secret`
   - `auth_url`, `token_url`, `api_url` pointing to the Keycloak realm
   - `scopes = openid profile email`
   - (Optional) group/role mapping

### 6) Smoke test

1. Visit `https://grafana.127.0.0.1.sslip.io/`.
2. Confirm redirect to Keycloak and return to Grafana authenticated session.

## Option B (lighter): VictoriaMetrics stack + Grafana + Loki/Tempo

1. Deploy `victoria-metrics-k8s-stack` (includes VM and dashboards; optionally Grafana).
2. Deploy Loki and Tempo as above.
3. Configure Grafana `auth.generic_oauth` to Keycloak as above.

## Cutover checklist

- `grafana.127.0.0.1.sslip.io` is live and protected by Keycloak.
- Metrics/traces/logs ingestion confirmed end-to-end.
- SigNoz routes are removed/disabled to avoid conflicts.
