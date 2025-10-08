"""FastAPI application for subnet calculator - Container/App Service version.

This version runs directly on Uvicorn (ASGI server) without Azure Functions wrapper.
Key differences from Azure Functions version:
- No AsgiMiddleware (FastAPI runs directly on Uvicorn)
- Standard routes (/subnets/ipv4) instead of function routes (/api/calculate_ipv4)
- Direct HTTP server instead of Azure Functions host
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from .config import get_auth_method, get_api_keys, AuthMethod
from .auth import validate_api_key
from .routers import health, subnets, auth

# Create FastAPI app
app = FastAPI(
    title="Subnet Calculator API",
    description="IPv4 and IPv6 subnet calculator with multiple authentication methods",
    version="1.0.0",
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
    openapi_url="/openapi.json",  # OpenAPI spec (for APIM import)
)

# Include routers
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(subnets.router)


# Middleware for authentication
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """Handle authentication based on AUTH_METHOD."""
    auth_method = get_auth_method()

    # Skip auth for health, docs, and auth endpoints
    if request.url.path in [
        "/health",
        "/health/ready",
        "/health/live",
        "/docs",
        "/redoc",
        "/openapi.json",
        "/auth/login",
        "/",
    ]:
        response = await call_next(request)
        return response

    # API key authentication via middleware
    if auth_method == AuthMethod.API_KEY:
        api_key = request.headers.get("X-API-Key")
        valid_keys = get_api_keys()
        if not validate_api_key(api_key, valid_keys):
            return JSONResponse(
                status_code=401, content={"detail": "Invalid or missing API key"}
            )

    # JWT, Azure SWA, APIM - handled by dependencies in route handlers
    # Pass through to let get_current_user dependency handle it
    if auth_method in (AuthMethod.JWT, AuthMethod.AZURE_SWA, AuthMethod.APIM):
        response = await call_next(request)
        return response

    # No authentication required (AUTH_METHOD=none)
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
        "openapi": "/openapi.json",
        "health": "/health",
    }
