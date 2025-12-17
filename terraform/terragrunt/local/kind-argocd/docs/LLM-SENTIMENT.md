# LLM Sentiment Analysis (kind-local)

This cluster includes a minimal “LLM sentiment analysis” workload intended to demonstrate:

- A tiny UI + API that can be reached from your laptop
- A separately-scoped “LLM service” namespace (to mimic calling an external dependency)
- Default-deny networking with explicit allow rules
- Simple persistence using an append-only CSV file

## Architecture

Namespaces:

- `sentiment-app`
  - `sentiment-frontend` (static UI)
  - `sentiment-api` (API + CSV storage)
- `sentiment-llm`
  - `ollama` (LLM runtime)

High-level request flow:

1. You open the UI in a browser.
2. The UI posts a comment to the API.
3. The API calls Ollama to classify sentiment.
4. The API appends the result to a CSV file on a PVC.

## Ingress patterns (how to call it from your laptop)

This repo uses **NGINX Gateway Fabric** (Gateway API) to expose services.

### UI (HTML/JS)

```text
https://sentiment.127.0.0.1.sslip.io/
```

### API (same hostname)

The UI calls the API on the same host using the `/api` prefix:

```text
https://sentiment.127.0.0.1.sslip.io/api/v1/comments
```

### API (dedicated hostname)

For API clients (Bruno / RapidAPI / curl) it can be convenient to have a dedicated hostname:

```text
https://sentiment-api.127.0.0.1.sslip.io/api/v1/comments
```

Notes:

- TLS is terminated at the gateway.
- The gateway routes to the `sentiment-app` services.
- Cross-namespace `HTTPRoute -> Service` access is enabled via a `ReferenceGrant` in `sentiment-app`.

## API endpoints

All endpoints are served by `sentiment-api`.

- `GET /healthz` -> basic health check
- `POST /api/v1/analyze` -> analyze a single comment (does not persist)
- `POST /api/v1/comments` -> analyze and persist
- `GET /api/v1/comments?limit=25` -> list recent saved items

Example:

```bash
curl -sk "https://sentiment-api.127.0.0.1.sslip.io/api/v1/comments?limit=5" | jq
```

## Storage (CSV persistence)

The API appends a row to an internal CSV file on a PersistentVolumeClaim.

- PVC: `sentiment-api-data` (namespace `sentiment-app`)
- File path in container: `/data/ratings.csv`

To view the last rows:

```bash
POD="$(kubectl -n sentiment-app get pod -l app.kubernetes.io/name=sentiment-api -o jsonpath='{.items[0].metadata.name}')"
kubectl -n sentiment-app exec -it "$POD" -- sh -lc 'tail -n 50 /data/ratings.csv'
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

- `sentiment-api -> ollama` (cluster-internal)
- DNS egress to kube-dns
- `ollama -> world:443` (only) so it can download model layers during preload

If you want a stricter egress posture, the next step is to replace `toEntities: world` with a narrow `toFQDNs` allow-list (or to host models internally).
