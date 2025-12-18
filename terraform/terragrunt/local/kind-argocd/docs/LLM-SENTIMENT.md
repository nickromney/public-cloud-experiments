# LLM Sentiment Analysis (kind-local)

This cluster includes a minimal “LLM sentiment analysis” workload intended to demonstrate:

- A tiny UI + API that can be reached from your laptop
- A separately-scoped “LLM service” namespace (to mimic calling an external dependency)
- Default-deny networking with explicit allow rules
- Simple persistence using an append-only CSV file

## Architecture

Namespaces:

- `dev`
  - `sentiment-frontend` (static UI)
- `uat`
  - `sentiment-frontend` (static UI)
- `sentiment`
  - `sentiment-api` (API + CSV storage)
- `sentiment-llm`
  - `ollama` (LLM runtime)
- `azure-apim-sim`
  - `apim-sentiment` + `apim-sentiment-uat` (API broker)

High-level request flow:

1. You open the UI in a browser.
2. The UI posts a comment to the API via the APIM simulator.
3. The API calls Ollama to classify sentiment.
4. The API appends the result to a CSV file on a PVC.

## Ingress patterns (how to call it from your laptop)

This repo uses **NGINX Gateway Fabric** (Gateway API) to expose services.

### UI (HTML/JS)

```text
https://sentiment.dev.127.0.0.1.sslip.io/
https://sentiment.uat.127.0.0.1.sslip.io/
```

### API (same hostname)

The UI calls the API on the same host using the `/api` prefix; the gateway routes `/api` to the APIM simulator:

```text
https://sentiment.dev.127.0.0.1.sslip.io/api/v1/comments
```

Notes:

- TLS is terminated at the gateway.
- The gateway routes `/` to `sentiment-frontend` in the relevant env namespace.
- The gateway routes `/api` to `apim-sentiment` (dev) or `apim-sentiment-uat` (uat) in `azure-apim-sim`.

## API endpoints

All endpoints are served by `sentiment-api`.

- `GET /healthz` -> basic health check
- `POST /api/v1/analyze` -> analyze a single comment (does not persist)
- `POST /api/v1/comments` -> analyze and persist
- `GET /api/v1/comments?limit=25` -> list recent saved items

Example:

```bash
curl -sk "https://sentiment.dev.127.0.0.1.sslip.io/api/v1/comments?limit=5" | jq
```

## Storage (CSV persistence)

The API appends a row to an internal CSV file on a PersistentVolumeClaim.

- PVC: `sentiment-api-data` (namespace `sentiment`)
- File path in container: `/data/ratings.csv`

To view the last rows:

```bash
POD="$(kubectl -n sentiment get pod -l app.kubernetes.io/name=sentiment-api -o jsonpath='{.items[0].metadata.name}')"
kubectl -n sentiment exec -it "$POD" -- sh -lc 'tail -n 50 /data/ratings.csv'
```

CSV schema:

```text
timestamp,label,confidence,latency_ms,text
```

## Model bootstrapping (preloading)

To avoid the first user request triggering a model download, the `ollama` Deployment uses an init container to preload the model into the shared PVC.

- Model: `qwen2.5:0.5b`
- Data dir: `/root/.ollama` (persisted to `ollama-data` PVC)

Operational note:

- The init container starts a temporary `ollama serve`, pulls the model, then exits.
- The main container starts normally after the model exists on disk.

## Networking / egress considerations

Both namespaces are labeled `kyverno.io/isolate=true`, which means they get a default-deny `NetworkPolicy`.

Connectivity is allowed explicitly via `CiliumNetworkPolicy`:

- `azure-auth-gateway-nginx -> sentiment-frontend` (dev/uat)
- `azure-auth-gateway-nginx -> apim-sentiment` (dev/uat)
- `apim-sentiment -> sentiment-api`
- `sentiment-api -> ollama`
- DNS egress to kube-dns
- `ollama -> world:443` (only) so it can download model layers during preload

Internal edges use Cilium mesh-auth with `authentication: { mode: required }`.

If you want a stricter egress posture, the next step is to replace `toEntities: world` with a narrow `toFQDNs` allow-list (or to host models internally).
