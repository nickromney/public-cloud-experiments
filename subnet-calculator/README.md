# Subnet Calculator

A full-stack IPv4/IPv6 subnet calculator with REST API backend and web frontend.

## Quick Start

### Using Docker Compose

Run both the API and frontend together:

```bash
docker compose up
```

Or build and run in detached mode:

```bash
docker compose up -d --build
```

Access the application at `http://localhost:8000` (frontend) and API at `http://localhost:8080` (backend).

### Using Podman Compose

Run both services:

```bash
podman-compose up
```

Or:

```bash
podman compose up
```

### Stopping Services

Docker Compose:

```bash
docker compose down
```

Podman Compose:

```bash
podman-compose down
```

## Project Structure

```text
subnet-calculator/
├── api-fastapi-azure-function/  # Backend API (FastAPI + Azure Functions)
├── frontend-python-flask/       # Frontend (Flask web application)
├── frontend-html-static/        # Static HTML frontend (pure client-side)
├── docker-compose.yml           # Docker Compose configuration
├── compose.yml                  # Podman Compose configuration
└── README.md                    # This file
```

## Individual Projects

See individual project READMEs for local development without containers:

- [API Documentation](api-fastapi-azure-function/README.md) - Backend REST API (FastAPI + Azure Functions)
- [Flask Frontend](frontend-python-flask/README.md) - Server-side rendering with Flask
- [Static Frontend](frontend-html-static/README.md) - Pure HTML/JS/CSS (demonstrates CORS, client-side architecture)

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

  **Flask (Server-Side Rendering)**:
  - Server calls API, renders HTML
  - Progressive enhancement (works without JavaScript)
  - CORS not required (server-to-server)
  - Python 3.11, Pico CSS

  **Static (Client-Side)**:
  - Browser calls API directly (CORS required)
  - Pure HTML/JS/CSS (no server runtime)
  - Deployable to GitHub Pages, S3, Azure Storage
  - Demonstrates "old way" of web development

## Container Details

The `docker-compose.yml` includes:

- Health checks for the API service
- Automatic dependency management (frontend waits for API to be healthy)
- Service networking (frontend connects to API via `http://api:80/api/v1`)
- Host port mappings (8080 for API, 8000 for frontend)

The `compose.yml` (Podman) has simplified configuration without health checks (as Podman Compose has limited support for `condition: service_healthy`).

## Troubleshooting

### Check container logs

Docker:

```bash
docker compose logs -f
docker compose logs api -f
docker compose logs frontend -f
```

Podman:

```bash
podman-compose logs -f
```

### Rebuild containers

Docker:

```bash
docker compose up --build
```

Podman:

```bash
podman-compose up --build
```

### Check service health

```bash
# API health check
curl http://localhost:8080/api/v1/health

# Frontend (should load HTML)
curl http://localhost:8000
```
