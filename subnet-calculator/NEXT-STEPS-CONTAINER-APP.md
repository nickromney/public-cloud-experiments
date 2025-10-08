# Next Steps: FastAPI Container App Implementation

## Overview

This document outlines the steps to create a non-Function-App version of our subnet calculator API that can run on:

- **Azure Container Apps** (recommended for microservices/containers)
- **Azure App Service** (traditional PaaS web apps)

Both can integrate with Azure API Management (APIM) using OpenAPI specifications.

## Key Differences from Azure Functions

### Current State (Azure Functions)

- Uses `azure-functions` Python library
- **Must use** `AsgiMiddleware` to bridge FastAPI → Azure Functions host
- Function-specific route pattern: `/api/{function_name}`
- Deployed as Function App with `func` CLI
- HTTP server: Azure Functions host (not Uvicorn)

**Why AsgiMiddleware?** Azure Functions requires it to translate between the ASGI protocol (FastAPI) and Azure Functions' HTTP trigger interface.

### Target State (Container App / App Service)

- Pure FastAPI application (no Azure Functions wrapper needed)
- **Uvicorn** as the ASGI server (FastAPI's recommended server)
- Direct route patterns: `/subnets/ipv4`, `/health`, etc.
- Deployed as container image or source code
- HTTP server: Uvicorn directly serving FastAPI

**Why Uvicorn?** It's the de facto standard ASGI server for FastAPI - fast, production-ready, and recommended by FastAPI documentation.

## Implementation Plan

### Phase 1: Create Standalone FastAPI Application

#### Step 1.1: Create New Directory Structure

```bash
mkdir -p subnet-calculator/api-fastapi-container-app
cd subnet-calculator/api-fastapi-container-app
```

**Files to create:**

```text
api-fastapi-container-app/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app entry point (no Azure Functions)
│   ├── config.py            # Environment config (copy from api-fastapi-azure-function)
│   ├── auth.py              # Authentication utilities (copy)
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── health.py        # Health check endpoints
│   │   └── subnets.py       # Subnet calculation endpoints
│   └── models/
│       ├── __init__.py
│       └── subnet.py        # Pydantic models
├── tests/
│   ├── __init__.py
│   ├── test_auth.py
│   ├── test_subnets.py
│   └── test_health.py
├── Dockerfile               # Multi-stage build for production
├── docker-compose.yml       # Local development
├── pyproject.toml           # uv dependencies
├── .dockerignore
└── README.md
```

#### Step 1.2: Create Pure FastAPI Application

**app/main.py** (no Azure Functions wrapper):

```python
"""FastAPI application for subnet calculator - Container/App Service version."""

from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from .config import get_settings, AuthMethod
from .auth import verify_api_key, get_current_user
from .routers import health, subnets
import time

# Create FastAPI app
app = FastAPI(
    title="Subnet Calculator API",
    description="IPv4 and IPv6 subnet calculator",
    version="1.0.0",
    docs_url="/docs",           # Swagger UI
    redoc_url="/redoc",         # ReDoc
    openapi_url="/openapi.json" # OpenAPI spec (for APIM import)
)

# Include routers
app.include_router(health.router)
app.include_router(subnets.router)

# Middleware for authentication and logging
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Handle authentication based on AUTH_METHOD."""
    settings = get_settings()

    # Skip auth for health and docs endpoints
    if request.url.path in ["/health", "/docs", "/redoc", "/openapi.json"]:
        return await call_next(request)

    # API key authentication via middleware
    if settings.auth_method == AuthMethod.API_KEY:
        api_key = request.headers.get("X-API-Key")
        if not verify_api_key(api_key):
            return JSONResponse(
                status_code=401,
                content={"detail": "Invalid or missing API key"}
            )

    # JWT, Azure SWA, APIM - handled by dependencies
    # Pass through to let get_current_user dependency handle it

    response = await call_next(request)
    return response

# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Subnet Calculator API",
        "version": "1.0.0",
        "docs": "/docs",
        "openapi": "/openapi.json"
    }
```

**app/routers/health.py**:

```python
"""Health check endpoints."""

from fastapi import APIRouter

router = APIRouter(prefix="", tags=["health"])

@router.get("/health")
async def health_check():
    """Health check endpoint (no authentication required)."""
    return {"status": "healthy"}

@router.get("/health/ready")
async def readiness_check():
    """Readiness check for Kubernetes/Container Apps."""
    # Add dependency checks here (database, etc.)
    return {"status": "ready"}

@router.get("/health/live")
async def liveness_check():
    """Liveness check for Kubernetes/Container Apps."""
    return {"status": "alive"}
```

**app/routers/subnets.py**:

```python
"""Subnet calculation endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from ..auth import get_current_user
from ..models.subnet import (
    SubnetIPv4Request,
    SubnetIPv4Response,
    SubnetIPv6Request,
    SubnetIPv6Response
)
# Import calculation logic from original implementation

router = APIRouter(prefix="/subnets", tags=["subnets"])

@router.post("/ipv4", response_model=SubnetIPv4Response)
async def calculate_ipv4_subnet(
    request: SubnetIPv4Request,
    current_user: str = Depends(get_current_user)
):
    """Calculate IPv4 subnet details."""
    # Implementation from api-fastapi-azure-function
    pass

@router.post("/ipv6", response_model=SubnetIPv6Response)
async def calculate_ipv6_subnet(
    request: SubnetIPv6Request,
    current_user: str = Depends(get_current_user)
):
    """Calculate IPv6 subnet details."""
    # Implementation from api-fastapi-azure-function
    pass
```

#### Step 1.3: Update Dependencies

**pyproject.toml**:

```toml
[project]
name = "subnet-calculator-api"
version = "1.0.0"
description = "FastAPI subnet calculator for Container Apps / App Service"
requires-python = ">=3.11"
dependencies = [
    "fastapi[standard]>=0.118.0",
    "uvicorn[standard]>=0.34.0",  # ASGI server
    "pwdlib[argon2]>=0.2.0",      # Password hashing
    "pyjwt>=2.10.1",              # JWT authentication
    "pydantic>=2.10.3",           # Data validation
    "pydantic-settings>=2.6.1",   # Environment config
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.4",
    "pytest-asyncio>=0.25.0",
    "httpx>=0.28.1",              # For TestClient
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

**Key differences from Azure Functions version:**

- **Remove** `azure-functions` library (not needed without AsgiMiddleware)
- **Add** `uvicorn[standard]` as the ASGI server (replaces Azure Functions host)
- FastAPI runs directly on Uvicorn instead of being wrapped by AsgiMiddleware

#### Step 1.4: Create Dockerfile

**Dockerfile** (multi-stage build):

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Set working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install dependencies to /app/.venv
RUN uv sync --frozen --no-dev

# Stage 2: Runtime
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY app ./app

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Run uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Key features:**

- Multi-stage build (smaller final image)
- Non-root user for security
- Health check for Container Apps
- **Uvicorn as ASGI server** - production-ready HTTP server for FastAPI

#### Step 1.5: Create Docker Compose for Local Development

**docker-compose.yml**:

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      # Authentication
      - AUTH_METHOD=jwt
      - JWT_SECRET_KEY=local-dev-secret-key-minimum-32-chars-long-123
      - JWT_ALGORITHM=HS256
      - JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
      # Test users (Argon2 hashed: demo=password123, admin=securepass)
      - JWT_TEST_USERS={"demo":"$$argon2id$$v=19$$m=65536,t=3,p=4$$TklhcmEkyMzqJaH3KHQQDA$$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo","admin":"$$argon2id$$v=19$$m=65536,t=3,p=4$$JiTJZlTwD/1jJLlMQMOwCA$$HbubnE11kzEfcszqKtMOmjvxj14vjooqbdZtgc1NYCs"}
    volumes:
      - ./app:/app/app  # Hot reload in development
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 10s
      timeout: 3s
      retries: 3
```

### Phase 2: OpenAPI Specification for APIM

#### Step 2.1: Ensure OpenAPI Spec is Available

FastAPI automatically generates OpenAPI spec at `/openapi.json`. APIM will look for it at:

1. `/openapi.json` (FastAPI default)
2. `/openapi.yml`
3. `/swagger/v1/swagger.json`

**No additional work needed** - FastAPI handles this automatically.

#### Step 2.2: Test OpenAPI Spec Locally

```bash
# Start the application
docker compose up

# View OpenAPI spec
curl http://localhost:8000/openapi.json | jq

# View Swagger UI
open http://localhost:8000/docs

# View ReDoc
open http://localhost:8000/redoc
```

#### Step 2.3: Customize OpenAPI Metadata (Optional)

**app/main.py** enhancements:

```python
from fastapi.openapi.utils import get_openapi

def custom_openapi():
    """Customize OpenAPI schema for APIM."""
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title="Subnet Calculator API",
        version="1.0.0",
        description="IPv4 and IPv6 subnet calculator with multiple authentication methods",
        routes=app.routes,
        servers=[
            {"url": "http://localhost:8000", "description": "Local development"},
            {"url": "https://api.example.com", "description": "Production (via APIM)"}
        ]
    )

    # Add security schemes for APIM documentation
    openapi_schema["components"]["securitySchemes"] = {
        "ApiKeyAuth": {
            "type": "apiKey",
            "in": "header",
            "name": "X-API-Key"
        },
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT"
        }
    }

    app.openapi_schema = openapi_schema
    return app.openapi_schema

app.openapi = custom_openapi
```

### Phase 3: Deployment to Azure

#### Option A: Azure Container Apps (Recommended)

**Why Container Apps:**

- Native container support
- Built-in ingress (HTTP/HTTPS)
- Auto-scaling (KEDA-based)
- Internal/external ingress options
- Managed certificates
- Integration with Virtual Networks

**Deployment steps:**

```bash
# Variables
RESOURCE_GROUP="rg-subnet-calc-prod"
LOCATION="eastus"
CONTAINER_APP_NAME="ca-subnet-calc-api"
CONTAINER_REGISTRY="crsubnetcalc"
CONTAINER_APP_ENV="cae-subnet-calc"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Container Registry
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_REGISTRY \
    --sku Basic \
    --admin-enabled true

# Build and push image
az acr build \
    --registry $CONTAINER_REGISTRY \
    --image subnet-calc-api:latest \
    --file Dockerfile .

# Create Container Apps environment
az containerapp env create \
    --name $CONTAINER_APP_ENV \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION

# Create Container App
az containerapp create \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINER_APP_ENV \
    --image $CONTAINER_REGISTRY.azurecr.io/subnet-calc-api:latest \
    --registry-server $CONTAINER_REGISTRY.azurecr.io \
    --registry-username $(az acr credential show -n $CONTAINER_REGISTRY --query username -o tsv) \
    --registry-password $(az acr credential show -n $CONTAINER_REGISTRY --query passwords[0].value -o tsv) \
    --target-port 8000 \
    --ingress external \
    --env-vars \
        AUTH_METHOD=apim \
    --min-replicas 1 \
    --max-replicas 10

# Get Container App URL
az containerapp show \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query properties.configuration.ingress.fqdn \
    -o tsv
```

**For internal-only access (with APIM in same VNET):**

```bash
# Create Container App with internal ingress
az containerapp create \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINER_APP_ENV \
    --image $CONTAINER_REGISTRY.azurecr.io/subnet-calc-api:latest \
    --ingress internal \  # Internal only - not publicly accessible
    # ... other parameters
```

#### Option B: Azure App Service

**Why App Service:**

- Simpler deployment model
- Built-in deployment slots (staging/production)
- Easy rollback
- Integrated with Azure DevOps / GitHub Actions
- Auto-scaling based on metrics

**Deployment steps:**

```bash
# Variables
RESOURCE_GROUP="rg-subnet-calc-prod"
LOCATION="eastus"
APP_SERVICE_PLAN="asp-subnet-calc"
WEB_APP_NAME="app-subnet-calc-api"

# Create App Service Plan (Linux)
az appservice plan create \
    --name $APP_SERVICE_PLAN \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --is-linux \
    --sku B1

# Create Web App with container
az webapp create \
    --name $WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN \
    --deployment-container-image-name $CONTAINER_REGISTRY.azurecr.io/subnet-calc-api:latest

# Configure container registry
az webapp config container set \
    --name $WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --docker-registry-server-url https://$CONTAINER_REGISTRY.azurecr.io \
    --docker-registry-server-user $(az acr credential show -n $CONTAINER_REGISTRY --query username -o tsv) \
    --docker-registry-server-password $(az acr credential show -n $CONTAINER_REGISTRY --query passwords[0].value -o tsv)

# Configure environment variables
az webapp config appsettings set \
    --name $WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        AUTH_METHOD=apim \
        WEBSITES_PORT=8000

# Get Web App URL
az webapp show \
    --name $WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query defaultHostName \
    -o tsv
```

### Phase 4: APIM Integration

#### Step 4.1: Import Container App into APIM

```bash
# Variables
APIM_NAME="apim-subnet-calc"
APIM_RESOURCE_GROUP="rg-subnet-calc-prod"
API_ID="subnet-calculator"

# Import Container App into APIM
az apim api import \
    --resource-group $APIM_RESOURCE_GROUP \
    --service-name $APIM_NAME \
    --api-id $API_ID \
    --path "/calculator" \
    --display-name "Subnet Calculator API" \
    --service-url "https://$CONTAINER_APP_NAME.region.azurecontainerapps.io" \
    --specification-format OpenApi \
    --specification-url "https://$CONTAINER_APP_NAME.region.azurecontainerapps.io/openapi.json"
```

**What happens:**

1. APIM fetches `/openapi.json` from Container App
2. Creates API operations for each endpoint
3. Maps routes: APIM `/calculator/*` → Container App `/*`

#### Step 4.2: Configure APIM Policies

**Inject user headers for backend:**

```xml
<policies>
    <inbound>
        <base />
        <!-- Validate JWT -->
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
            <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
            <audiences>
                <audience>api://subnet-calculator</audience>
            </audiences>
        </validate-jwt>

        <!-- Extract claims and inject headers for backend -->
        <set-header name="X-User-ID" exists-action="override">
            <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject)</value>
        </set-header>
        <set-header name="X-User-Email" exists-action="override">
            <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Claims.GetValueOrDefault("email", ""))</value>
        </set-header>

        <!-- Remove Authorization header (backend uses injected headers) -->
        <set-header name="Authorization" exists-action="delete" />

        <!-- Rate limiting -->
        <rate-limit calls="100" renewal-period="60" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

**Backend expects:** `AUTH_METHOD=apim` and trusts `X-User-ID` / `X-User-Email` headers.

### Phase 5: Testing

#### Step 5.1: Local Testing

```bash
cd api-fastapi-container-app

# Start with docker compose
docker compose up

# Test health endpoint (no auth)
curl http://localhost:8000/health

# Test with JWT
# 1. Get token
TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
    -H "Content-Type: application/json" \
    -d '{"username":"demo","password":"password123"}' \
    | jq -r .access_token)

# 2. Call API
curl -X POST http://localhost:8000/subnets/ipv4 \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"network":"192.168.1.0","prefix_length":24}'
```

#### Step 5.2: Container App Testing

```bash
# Get Container App URL
CONTAINER_APP_URL=$(az containerapp show \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

# Test health
curl https://$CONTAINER_APP_URL/health

# Test OpenAPI spec (for APIM)
curl https://$CONTAINER_APP_URL/openapi.json | jq
```

#### Step 5.3: APIM Testing

```bash
# Get APIM gateway URL
APIM_GATEWAY=$(az apim show \
    --name $APIM_NAME \
    --resource-group $APIM_RESOURCE_GROUP \
    --query gatewayUrl \
    -o tsv)

# Test via APIM (with JWT)
curl -X POST $APIM_GATEWAY/calculator/subnets/ipv4 \
    -H "Authorization: Bearer $AZURE_AD_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"network":"192.168.1.0","prefix_length":24}'
```

## Key Changes from Azure Functions Version

### Code Changes

| Aspect | Azure Functions | Container App / App Service |
|--------|----------------|----------------------------|
| Entry point | `function_app.py` with `@app.function_name()` | `main.py` with `FastAPI()` |
| ASGI wrapper | `AsgiMiddleware` (required for Azure Functions) | None (FastAPI runs directly) |
| Routes | `/api/{function}` | `/subnets/ipv4`, etc. |
| HTTP Server | Azure Functions host | **Uvicorn** (ASGI server) |
| Dependencies | `azure-functions` + `fastapi` | `fastapi` + `uvicorn` |
| Deployment | `func` CLI | Docker image |
| Why wrapper? | Functions host requires AsgiMiddleware bridge | Uvicorn natively speaks ASGI |

### Authentication Flow

**Functions + APIM:**

```text
Client → APIM → Azure Function (AUTH_METHOD=apim, trusts headers)
```

**Container App + APIM:**

```text
Client → APIM → Container App (AUTH_METHOD=apim, trusts headers)
```

**Same authentication code** - just different deployment target.

### Infrastructure

| Resource | Azure Functions | Container App |
|----------|----------------|---------------|
| Compute | Function App | Container App |
| Scaling | Consumption/Premium plan | KEDA-based auto-scaling |
| Networking | VNET integration | Built-in VNET support |
| Ingress | Function host | Native HTTP ingress |
| Cost model | Per execution | Per vCPU/memory second |

## Migration Checklist

- [x] Create `api-fastapi-container-app` directory structure
- [x] Copy and adapt code from `api-fastapi-azure-function`
  - [x] Remove Azure Functions wrapper
  - [x] Create pure FastAPI `main.py`
  - [x] Create routers (`health.py`, `subnets.py`, `auth.py`)
  - [x] Copy models, auth, config unchanged
  - [x] Create `auth_utils.py` for `get_current_user` dependency
- [x] Update `pyproject.toml` (remove `azure-functions`, add `uvicorn`)
- [x] Create `Dockerfile` with multi-stage build
- [x] Create `docker-compose.yml` for local testing
- [x] Test locally with Podman Compose
  - [x] Health endpoints working
  - [x] JWT authentication working
  - [x] Subnet calculation endpoints working
  - [x] OpenAPI docs accessible
- [ ] Choose deployment target (Container Apps or App Service)
- [ ] Deploy to Azure
- [ ] Verify OpenAPI spec is accessible (`/openapi.json`)
- [ ] Import into APIM using Azure Portal or CLI
- [ ] Configure APIM policies (JWT validation, header injection)
- [ ] Test end-to-end: Client → APIM → Container App
- [ ] Add to CI/CD pipeline (GitHub Actions or Azure DevOps)

## Phase 1 Complete

The pure FastAPI container app is working locally with:

- **Uvicorn ASGI server** (no Azure Functions wrapper)
- **JWT authentication** with login endpoint
- **All subnet calculation endpoints** (IPv4, IPv6, validate, check-private, check-cloudflare)
- **Health endpoints** for Kubernetes/Container Apps probes
- **OpenAPI documentation** at `/docs` and `/redoc`
- **Multi-stage Docker build** for production
- **Podman/Docker Compose** for local development

**Tested and verified:**

```bash
# All endpoints working
GET  /health
GET  /health/ready
GET  /health/live
GET  /docs
GET  /openapi.json
POST /auth/login
POST /subnets/ipv4 (with JWT)
```

## Benefits of This Approach

1. **Pure FastAPI** - No Azure-specific wrappers (no AsgiMiddleware needed), more portable
2. **Standard deployment** - Works on any container platform (Azure, AWS, GCP, Kubernetes)
3. **Better local development** - Direct Uvicorn without Azure Functions host emulation
4. **Easier debugging** - Standard ASGI application served by Uvicorn
5. **Cost optimization** - Container Apps can be cheaper for steady workloads
6. **More control** - Direct access to Uvicorn configuration (workers, timeout, graceful shutdown, etc.)
7. **Same authentication code** - Reuse all auth logic from Functions version
8. **Industry standard** - Uvicorn is the recommended server in FastAPI documentation

**Trade-off:** Azure Functions provides serverless scaling (pay-per-execution). Container Apps requires always-on containers (even if scaled to 1 replica). Choose based on your traffic patterns.

## Next Step

Start with **Step 1.1** - create the directory structure and begin porting the code to a pure FastAPI application.
