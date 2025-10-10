# Subnet Calculator

A full-stack IPv4/IPv6 subnet calculator with multiple backend and frontend implementations demonstrating different deployment patterns.

## Quick Start

### Run All Services

The project includes **four complete stacks** that run simultaneously:

```bash
# Start all six services (2 backends + 4 frontends)
podman-compose up -d

# Or with Docker
docker compose up -d
```

**Stack 1 - Flask + Azure Function** (Traditional):

- Flask Frontend: <http://localhost:8000>
- Azure Function API: <http://localhost:8080/api/v1/docs>

**Stack 2 - Static HTML + Container App** (Client-Side):

- Static HTML Frontend: <http://localhost:8001>
- Container App API: <http://localhost:8090/api/v1/docs>

**Stack 3 - Flask + Container App** (Server-Side):

- Flask Frontend: <http://localhost:8002>
- Container App API: <http://localhost:8090/api/v1/docs>

**Stack 4 - TypeScript Vite + Container App** (Modern SPA):

- Vite SPA: <http://localhost:3000>
- Container App API: <http://localhost:8090/api/v1/docs>

### Run Individual Stacks

**Stack 1 - Flask + Azure Function:**

```bash
podman-compose up api-fastapi-azure-function frontend-python-flask
```

**Stack 2 - Static HTML + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-html-static
```

**Stack 3 - Flask + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-python-flask-container-app
```

**Stack 4 - TypeScript Vite + Container App:**

```bash
podman-compose up api-fastapi-container-app frontend-typescript-vite
```

### Run Individual Services

Each component can run standalone from its directory:

```bash
# Azure Function API only (port 8080)
cd api-fastapi-azure-function && podman-compose up

# Container App API only (port 8090)
cd api-fastapi-container-app && podman-compose up

# Flask Frontend only (port 8000)
cd frontend-python-flask && podman-compose up

# Static Frontend only (port 8001)
cd frontend-html-static && podman-compose up
```

### Stopping Services

```bash
podman-compose down
# or
docker compose down
```

## Project Structure

```text
subnet-calculator/
├── api-fastapi-azure-function/  # Azure Function API (port 8080)
│   ├── compose.yml              # Standalone compose file
│   ├── test_endpoints.sh        # API endpoint tests
│   └── README.md
├── api-fastapi-container-app/   # Container App API (port 8090)
│   ├── compose.yml              # Standalone compose file
│   ├── test_endpoints.sh        # API endpoint tests with JWT
│   └── README.md
├── frontend-python-flask/       # Flask Frontend (port 8000)
│   ├── compose.yml              # Standalone compose file
│   ├── test_frontend.py         # Playwright e2e tests
│   └── README.md
├── frontend-html-static/        # Static HTML Frontend (port 8001)
│   ├── compose.yml              # Standalone compose file
│   ├── test_frontend.py         # Playwright e2e tests
│   ├── Dockerfile               # nginx-based image
│   ├── nginx.conf               # API proxy configuration
│   └── README.md
├── frontend-typescript-vite/    # TypeScript Vite Frontend (port 3000)
│   ├── compose.yml              # Standalone compose file
│   ├── tests/frontend.spec.ts   # Playwright e2e tests (15 tests)
│   ├── Dockerfile               # Multi-stage build (Node.js -> nginx)
│   ├── nginx.conf               # API proxy configuration
│   └── README.md
├── compose.yml                  # Main compose file (all 4 stacks)
├── TESTING.md                   # Complete testing guide
└── README.md                    # This file
```

## Service Details

| Service | Type | Port | Connects To | Description |
|---------|------|------|-------------|-------------|
| `api-fastapi-azure-function` | Backend | 8080 | - | FastAPI via Azure Functions AsgiMiddleware |
| `api-fastapi-container-app` | Backend | 8090 | - | FastAPI on Uvicorn (includes IPv6, no auth in compose) |
| `frontend-python-flask` | Frontend | 8000 | Azure Function API | Server-side Flask (Stack 1) |
| `frontend-html-static` | Frontend | 8001 | Container App API | Static HTML with nginx proxy (Stack 2) |
| `frontend-python-flask-container-app` | Frontend | 8002 | Container App API | Server-side Flask (Stack 3) |
| `frontend-typescript-vite` | Frontend | 3000 | Container App API | TypeScript + Vite SPA (Stack 4) |

## Individual Projects

See individual project READMEs for local development and detailed information:

- [Azure Function API](api-fastapi-azure-function/README.md) - Traditional Azure Functions deployment
- [Container App API](api-fastapi-container-app/README.md) - Modern container-native deployment
- [Flask Frontend](frontend-python-flask/README.md) - Server-side rendering (no CORS needed)
- [Static Frontend](frontend-html-static/README.md) - Pure client-side HTML/JS with nginx proxy
- [TypeScript Vite Frontend](frontend-typescript-vite/README.md) - Modern SPA with TypeScript, Vite, and nginx proxy

## Architecture

- **Backend API**: FastAPI-based Azure Function App

  - IPv4/IPv6 address validation and CIDR notation support
  - RFC1918 private address detection
  - RFC6598 shared address space detection
  - Cloudflare IP range detection
  - Cloud provider-specific subnet calculations (Azure, AWS, OCI, Standard)
  - Interactive Swagger UI documentation at `/api/v1/docs`
  - Python 3.11

- **Frontends**:

  **Flask (Server-Side Rendering)** - Stacks 1 & 3:
  - Server calls API, renders HTML
  - Progressive enhancement (works without JavaScript)
  - CORS not required (server-to-server)
  - Python 3.11, Pico CSS

  **Static HTML (Client-Side)** - Stack 2:
  - Pure HTML/JS/CSS (no server runtime)
  - nginx reverse proxy forwards `/api/*` to backend
  - Browser makes relative API calls
  - Architecture: `Browser → nginx (port 8001) → Backend API (container network)`

  **TypeScript + Vite (Modern SPA)** - Stack 4:
  - TypeScript (ES2022/ES2023), Vite 6.0
  - Multi-stage Docker build (Node.js build → nginx serve)
  - nginx reverse proxy forwards `/api/*` to backend
  - Type-safe API client with full interfaces
  - Architecture: `Browser → nginx (port 3000) → Backend API (container network)`
  - Comprehensive Playwright tests (15 tests)

## Container Details

The main `compose.yml` runs all six services (2 backends + 4 frontends):

- **Platform**: linux/amd64 (for deployment compatibility)
- **Health checks**: Configured for both API services
- **Networking**: Services communicate via Docker/Podman network
- **Port Mappings**:
  - Azure Function API: 8080 → 80 (internal)
  - Container App API: 8090 → 8000 (internal)
  - Flask Frontend (Stack 1): 8000
  - Static Frontend (Stack 2): 8001
  - Flask Frontend (Stack 3): 8002
  - TypeScript Vite Frontend (Stack 4): 3000

**Four Complete Stacks**:

1. **Flask + Azure Function** (8000/8080) - Traditional server-side rendering
2. **Static HTML + Container App** (8001/8090) - Client-side with nginx API proxy
3. **Flask + Container App** (8002/8090) - Server-side rendering with modern API
4. **TypeScript Vite + Container App** (3000/8090) - Modern SPA with nginx API proxy

### nginx Reverse Proxy Pattern (Stacks 2 & 4)

Both client-side frontends (Static HTML and TypeScript Vite) use nginx as a reverse proxy to avoid CORS issues:

**Configuration** (`nginx.conf`):

```nginx
location /api/ {
    proxy_pass http://api-fastapi-container-app:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

**How it works**:

1. Browser requests `/api/v1/health` from frontend container
2. nginx intercepts and proxies to backend container via Docker network
3. Backend responds to nginx, nginx returns to browser
4. **Benefits**: No CORS configuration needed, same-origin from browser perspective

Each subdirectory contains a standalone `compose.yml` for individual service development.

## Troubleshooting

### Check container logs

```bash
# All services
podman-compose logs -f
# or
docker compose logs -f

# Individual services
podman-compose logs api-fastapi-azure-function -f
podman-compose logs api-fastapi-container-app -f
podman-compose logs frontend-python-flask -f
podman-compose logs frontend-html-static -f
podman-compose logs frontend-python-flask-container-app -f
```

### Rebuild containers

```bash
podman-compose up --build
# or
docker compose up --build
```

### Check service health

```bash
# Azure Function API
curl http://localhost:8080/api/v1/health

# Container App API (no auth in compose)
curl http://localhost:8090/api/v1/health

# Flask Frontend (Stack 1 - connects to Azure Function)
curl http://localhost:8000

# Static Frontend (Stack 2 - connects to Container App)
curl http://localhost:8001

# Flask Frontend (Stack 3 - connects to Container App)
curl http://localhost:8002

# TypeScript Vite SPA (Stack 4 - connects to Container App)
curl http://localhost:3000
```
