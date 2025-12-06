"""Lightweight API Management simulator for Stack 12.

The service validates OAuth2/OIDC bearer tokens issued by Keycloak, optionally checks
for an `Ocp-Apim-Subscription-Key`, and forwards the request to the FastAPI backend.
It injects Easy Auth style headers so downstream services can identify the caller.
"""

from __future__ import annotations

import base64
from contextlib import asynccontextmanager
import json
import logging
import os
from typing import Any, Dict

import httpx
import jwt
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from jwt import InvalidTokenError, PyJWKClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("apim-simulator")

API_BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://api-fastapi-keycloak:80")
APIM_SUBSCRIPTION_KEY = os.getenv("APIM_SUBSCRIPTION_KEY", "")
OIDC_ISSUER = os.getenv("OIDC_ISSUER", "http://localhost:8180/realms/subnet-calculator")
OIDC_AUDIENCE = os.getenv("OIDC_AUDIENCE", "api-app")
OIDC_JWKS_URI = os.getenv(
    "OIDC_JWKS_URI", "http://keycloak:8080/realms/subnet-calculator/protocol/openid-connect/certs"
)
ALLOW_ANONYMOUS = os.getenv("ALLOW_ANONYMOUS", "false").lower() == "true"
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("ALLOWED_ORIGINS", "http://localhost:3007").split(",")
    if origin.strip()
]

if not ALLOWED_ORIGINS:
    ALLOWED_ORIGINS = ["*"]

jwks_client = PyJWKClient(OIDC_JWKS_URI)
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    app.state.http_client = httpx.AsyncClient(timeout=httpx.Timeout(30.0))
    logger.info(
        "APIM simulator ready | backend=%s | issuer=%s | audience=%s | origins=%s",
        API_BACKEND_BASE_URL,
        OIDC_ISSUER,
        OIDC_AUDIENCE,
        ALLOWED_ORIGINS,
    )
    yield
    # Shutdown
    http_client: httpx.AsyncClient = app.state.http_client
    await http_client.aclose()


app = FastAPI(title="Subnet Calculator APIM Simulator", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def build_client_principal(claims: Dict[str, Any]) -> str:
    principal = {
        "auth_typ": "oauth2",
        "name_typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
        "role_typ": "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
        "claims": [
            {"typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", "val": claims.get("sub", "")},
            {"typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "val": claims.get("name", "")},
            {"typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress", "val": claims.get("email", "")},
            {"typ": "preferred_username", "val": claims.get("preferred_username", "")},
        ],
    }
    return base64.b64encode(json.dumps(principal).encode("utf-8")).decode("utf-8")


def validate_subscription_key(request: Request) -> None:
    if not APIM_SUBSCRIPTION_KEY:
        logger.warning("APIM_SUBSCRIPTION_KEY not set - subscription key validation is disabled")
        return

    provided_key = request.headers.get("ocp-apim-subscription-key") or request.headers.get("x-ocp-apim-subscription-key")
    if not provided_key:
        raise HTTPException(status_code=401, detail="Missing subscription key")

    if provided_key != APIM_SUBSCRIPTION_KEY:
        raise HTTPException(status_code=401, detail="Invalid subscription key")


def authenticate_request(request: Request) -> Dict[str, Any]:
    if ALLOW_ANONYMOUS:
        # Local/demo mode: bypass auth and use a fixed identity
        return {
            "sub": "anon-demo",
            "email": "demo@example.com",
            "name": "Demo User",
            "preferred_username": "demo",
            "iss": OIDC_ISSUER,
            "aud": OIDC_AUDIENCE,
        }

    validate_subscription_key(request)

    auth_header = request.headers.get("authorization")
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    token = auth_header.split(" ", 1)[1].strip()

    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=OIDC_AUDIENCE,
            issuer=OIDC_ISSUER,
        )
        return claims
    except InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc


def build_upstream_headers(request: Request, claims: Dict[str, Any]) -> Dict[str, str]:
    headers: Dict[str, str] = {
        key: value for key, value in request.headers.items() if key.lower() not in HOP_BY_HOP_HEADERS
    }

    headers["x-apim-user-object-id"] = claims.get("sub", "")
    headers["x-apim-user-email"] = claims.get("email", "")
    headers["x-apim-user-name"] = claims.get("name", claims.get("preferred_username", ""))
    headers["x-apim-auth-method"] = "oidc"
    headers["x-ms-client-principal"] = build_client_principal(claims)
    headers["x-ms-client-principal-name"] = claims.get("preferred_username", "")

    return headers


def filter_response_headers(upstream_headers: Dict[str, str]) -> Dict[str, str]:
    headers = {key: value for key, value in upstream_headers.items() if key.lower() not in HOP_BY_HOP_HEADERS}
    headers["x-apim-simulator"] = "stack12"
    return headers


@app.get("/apim/health")
async def health() -> Dict[str, str]:
    return {"status": "healthy"}


@app.api_route("/api/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
async def proxy_request(full_path: str, request: Request) -> Response:
    if request.method == "OPTIONS":
        # Allow CORS preflight without authentication
        return Response(status_code=204)

    claims = authenticate_request(request)

    upstream_url = f"{API_BACKEND_BASE_URL}/api/{full_path}"
    body = await request.body()
    headers = build_upstream_headers(request, claims)
    client: httpx.AsyncClient = request.app.state.http_client

    try:
        upstream_response = await client.request(
            request.method,
            upstream_url,
            content=body,
            headers=headers,
            params=request.query_params,
        )
    except httpx.RequestError as exc:
        logger.exception("Unable to reach backend API")
        raise HTTPException(status_code=502, detail="Backend API unavailable") from exc

    response_headers = filter_response_headers(dict(upstream_response.headers))
    return Response(
        content=upstream_response.content,
        status_code=upstream_response.status_code,
        headers=response_headers,
        media_type=upstream_response.headers.get("content-type"),
    )


@app.get("/apim/user")
async def current_user(request: Request) -> Dict[str, Any]:
    claims = authenticate_request(request)
    return {
        "name": claims.get("name") or claims.get("preferred_username"),
        "email": claims.get("email"),
        "preferred_username": claims.get("preferred_username"),
        "sub": claims.get("sub"),
        "issuer": claims.get("iss"),
        "aud": claims.get("aud"),
    }
