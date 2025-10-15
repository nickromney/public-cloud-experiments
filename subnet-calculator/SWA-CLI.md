# Azure Static Web Apps CLI - Local Development

This project uses Azure Static Web Apps CLI to emulate the cloud environment locally.

## Quick Start

### Stack 4: TypeScript + Azure Function (No Auth)

```bash
npm run swa -- start stack4-no-auth
```

Access at: **<http://localhost:4280>**

- SWA CLI automatically starts:
  - Vite dev server (port 5173)
  - Azure Function API (port 7071) with `AUTH_METHOD=none`

---

### Stack 5: TypeScript + Azure Function (JWT Auth)

```bash
npm run swa -- start stack5-jwt
```

Access at: **<http://localhost:4281>**

- SWA CLI automatically starts:
  - Vite dev server (port 5173)
  - Azure Function API (port 7071) with `AUTH_METHOD=jwt`

---

## What SWA CLI Does

- Proxies frontend dev server (Vite at <http://localhost:5173>)
- Proxies API server (Container App at :8000 or Azure Function at :7071)
- Emulates Azure Static Web Apps routing
- Mocks authentication/authorization
- Serves everything through single port (4280 or 4281)

## Testing

### Stack 4 Tests

```bash
# Terminal 1: Start Container App API
cd api-fastapi-container-app
uv run uvicorn app.main:app --reload --port 8000

# Terminal 2: Start SWA CLI
npm run swa -- start stack4

# Terminal 3: Run tests
cd frontend-typescript-vite
npm run test:swa:stack4
```

### Stack 5 Tests

```bash
# Terminal 1: Start SWA CLI
npm run swa -- start stack5

# Terminal 2: Run tests
cd frontend-typescript-vite
npm run test:swa:stack5
```

## Configuration

Configuration is in `swa-cli.config.json`:

- **stack4**: Container App backend (FastAPI/Uvicorn) - requires manual start
- **stack5**: Azure Function backend - auto-started by SWA CLI via `func start`

## Why Two Terminals for Stack 4?

Azure Functions can be started automatically by SWA CLI (`func start`), but Container App (FastAPI with Uvicorn) is not an Azure Function, so it must be started manually.

For Stack 5, SWA CLI can start everything because it knows how to run Azure Functions.

## Troubleshooting

### Port already in use

```bash
# Kill process on port 4280 or 4281
lsof -ti:4280 | xargs kill -9
lsof -ti:4281 | xargs kill -9
```

### API not starting

**Stack 4**: Check that Container App API is running on port 8000

```bash
curl http://localhost:8000/api/v1/health
```

**Stack 5**: Check Azure Functions Core Tools is installed

```bash
func --version
```

### Frontend not proxying

Check that Vite dev server is running on port 5173:

```bash
curl http://localhost:5173
```

## Documentation

- [SWA CLI Docs](https://azure.github.io/static-web-apps-cli/)
- [Local Development Guide](https://learn.microsoft.com/en-us/azure/static-web-apps/local-development)
