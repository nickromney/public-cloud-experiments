import azure.functions as func
import fastapi
from fastapi import HTTPException, Request, Response, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.openapi.docs import get_swagger_ui_html, get_redoc_html
from fastapi.openapi.utils import get_openapi
from pydantic import BaseModel, Field
from ipaddress import (
    ip_address,
    ip_network,
    IPv4Address,
    IPv6Address,
    IPv4Network,
    IPv6Network,
    AddressValueError,
    NetmaskValueError,
)
import logging
import os
import sys
from importlib.metadata import version
from datetime import timedelta
import jwt

# Authentication imports
from config import (
    AuthMethod,
    get_auth_method,
    get_api_keys,
    get_jwt_secret_key,
    get_jwt_algorithm,
    get_jwt_expiration_minutes,
    get_jwt_test_users,
    validate_configuration,
)
from auth import (
    validate_api_key,
    create_access_token,
    decode_access_token,
    verify_test_user,
)

# Startup logging using print() to ensure visibility in Azure Functions logs
print("=" * 60, flush=True)
print("FUNCTION APP STARTING", flush=True)
print("=" * 60, flush=True)
print(f"Python version: {sys.version.split()[0]}", flush=True)
print(f"FastAPI version: {version('fastapi')}", flush=True)
print(f"Azure Functions version: {version('azure-functions')}", flush=True)

# Check for Managed Identity configuration
azure_client_id = os.getenv("AZURE_CLIENT_ID")
msi_endpoint = os.getenv("MSI_ENDPOINT")
identity_endpoint = os.getenv("IDENTITY_ENDPOINT")

if azure_client_id and (msi_endpoint or identity_endpoint):
    print(
        f"✅ MANAGED IDENTITY: User-assigned (Client ID: {azure_client_id})", flush=True
    )
elif msi_endpoint or identity_endpoint:
    print(
        "✅ MANAGED IDENTITY: System-assigned (or user-assigned without explicit client ID)",
        flush=True,
    )
else:
    print("ℹ️  MANAGED IDENTITY: Not available", flush=True)

# Log deployment environment
functions_worker_runtime = os.getenv("FUNCTIONS_WORKER_RUNTIME", "unknown")
azure_functions_env = os.getenv("AZURE_FUNCTIONS_ENVIRONMENT", "Development")
print(f"Runtime: {functions_worker_runtime}", flush=True)
print(f"Environment: {azure_functions_env}", flush=True)

# Validate and log authentication configuration
try:
    validate_configuration()
    auth_method = get_auth_method()
    print(f"Authentication: {auth_method.value}", flush=True)
    if auth_method == AuthMethod.API_KEY:
        api_keys = get_api_keys()
        print(f"API Keys configured: {len(api_keys)}", flush=True)
    elif auth_method == AuthMethod.JWT:
        test_users = get_jwt_test_users()
        algorithm = get_jwt_algorithm()
        expiration = get_jwt_expiration_minutes()
        print(f"JWT Algorithm: {algorithm}", flush=True)
        print(f"JWT Expiration: {expiration} minutes", flush=True)
        print(f"JWT Test Users: {len(test_users)}", flush=True)
except ValueError as e:
    print(f"[ERROR] Authentication configuration error: {e}", flush=True)
    raise

print("=" * 60, flush=True)
print("FUNCTION APP READY", flush=True)
print("=" * 60, flush=True)

logger = logging.getLogger(__name__)


# Pydantic models for request validation
class ValidateRequest(BaseModel):
    address: str = Field(..., description="IP address or CIDR notation")


class SubnetInfoRequest(BaseModel):
    network: str = Field(..., description="Network in CIDR notation")
    mode: str = Field(
        default="Azure", description="Cloud provider mode: Azure, AWS, OCI, or Standard"
    )


# Create FastAPI app with OpenAPI documentation
# Docs endpoints are disabled here and protected with custom endpoints below
api = fastapi.FastAPI(
    title="IPv4 Subnet Validation API",
    description="IPv4/IPv6 address validation, subnet calculations, and cloud provider IP analysis",
    version="1.0.0",
    docs_url=None,  # Disable default docs - we'll create protected custom endpoint
    redoc_url=None,  # Disable default redoc - we'll create protected custom endpoint
    openapi_url=None,  # Disable default openapi.json - we'll create protected custom endpoint
)

# Add CORS middleware
# Note: host.json CORS settings don't work with func start (local development)
# This middleware ensures CORS works both locally and in production
api.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For production, replace with specific origins
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Accept"],
)

# OAuth2 scheme for JWT authentication
# tokenUrl points to our login endpoint
# auto_error=False means we handle AUTH_METHOD flag ourselves
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)


async def get_current_user(request: Request) -> str:
    """
    Dependency that validates authentication based on AUTH_METHOD.

    - AUTH_METHOD=none: Returns "anonymous" (no auth required)
    - AUTH_METHOD=api_key: Validates X-API-Key header (handled by middleware)
    - AUTH_METHOD=jwt: Validates JWT token from Authorization: Bearer

    Args:
        request: FastAPI Request object to access headers

    Returns:
        str: Username from token's 'sub' claim, "anonymous", or "api_key_user"

    Raises:
        HTTPException: 401 if authentication fails
    """
    auth_method = get_auth_method()

    # No authentication required
    if auth_method == AuthMethod.NONE:
        return "anonymous"

    # API key authentication - middleware handles it
    # This dependency just passes through
    if auth_method == AuthMethod.API_KEY:
        return "api_key_user"

    # JWT authentication
    if auth_method == AuthMethod.JWT:
        # Manually parse Authorization header for better error messages
        authorization = request.headers.get("Authorization")

        # Missing Authorization header
        if not authorization:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing authorization header",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Strip whitespace and parse scheme and token
        authorization = authorization.strip()

        if not authorization:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Empty authorization header",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Split by whitespace (handles multiple spaces)
        parts = authorization.split()

        # Check for Bearer scheme
        if len(parts) == 0 or parts[0].lower() != "bearer":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization scheme. Expected Bearer",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Check for token
        if len(parts) != 2:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization header format",
                headers={"WWW-Authenticate": "Bearer"},
            )

        token = parts[1]

        # Validate JWT token
        try:
            secret_key = get_jwt_secret_key()
            algorithm = get_jwt_algorithm()
            payload = decode_access_token(token, secret_key, algorithm)

            username = payload.get("sub")
            if username is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Could not validate credentials",
                    headers={"WWW-Authenticate": "Bearer"},
                )

            return username

        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
                headers={"WWW-Authenticate": "Bearer"},
            )
        except jwt.InvalidTokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
                headers={"WWW-Authenticate": "Bearer"},
            )

    # Azure Static Web Apps EasyAuth
    if auth_method == AuthMethod.AZURE_SWA:
        # SWA injects x-ms-client-principal header after authentication
        principal_header = request.headers.get("x-ms-client-principal")

        if not principal_header:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Azure SWA authentication required but no principal found",
            )

        try:
            # Decode base64-encoded JSON
            import base64
            import json

            principal_json = base64.b64decode(principal_header).decode("utf-8")
            claims = json.loads(principal_json)

            # Extract user identity from claims
            # userDetails: email address (for AAD, GitHub, etc.)
            # userId: unique user ID
            # identityProvider: aad, github, google, twitter, etc.
            user_details = claims.get("userDetails")
            user_id = claims.get("userId")
            claims.get("identityProvider")

            # Return email if available, otherwise user ID
            user = user_details or user_id

            if not user:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid Azure SWA principal: missing user identity",
                )

            return user

        except (ValueError, KeyError, json.JSONDecodeError) as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid Azure SWA principal: {str(e)}",
            )

    # Azure API Management (APIM)
    if auth_method == AuthMethod.APIM:
        # APIM validates JWT and injects user claims into headers
        # Common headers set by APIM policies:
        # - X-User-ID: User identifier from JWT sub claim
        # - X-User-Email: User email from JWT email claim
        # - X-User-Roles: Comma-separated roles

        user_id = request.headers.get("X-User-ID")
        user_email = request.headers.get("X-User-Email")

        # Prefer email, fall back to user ID
        user = user_email or user_id

        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="APIM authentication required but no user headers found",
            )

        return user

    # Unknown auth method
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Authentication method not implemented",
    )


# Add authentication middleware
@api.middleware("http")
async def authentication_middleware(request: Request, call_next):
    """
    Authentication middleware that checks API keys based on AUTH_METHOD.

    - AUTH_METHOD=none: No authentication required (backward compatible)
    - AUTH_METHOD=api_key: Requires valid X-API-Key header
    """
    auth_method = get_auth_method()

    # No auth mode - allow all requests
    if auth_method == AuthMethod.NONE:
        response = await call_next(request)
        return response

    # API key authentication
    if auth_method == AuthMethod.API_KEY:
        api_key = request.headers.get("X-API-Key")

        # Missing API key
        if not api_key:
            return Response(
                content='{"detail":"Missing X-API-Key header"}',
                status_code=401,
                media_type="application/json",
            )

        # Validate API key
        valid_keys = get_api_keys()
        if not validate_api_key(api_key, valid_keys):
            return Response(
                content='{"detail":"Invalid API key"}',
                status_code=401,
                media_type="application/json",
            )

        # Valid API key - proceed
        response = await call_next(request)
        return response

    # JWT, Azure SWA, and APIM authentication - handled by dependencies, not middleware
    # Pass through to let get_current_user dependency handle it
    if auth_method in (AuthMethod.JWT, AuthMethod.AZURE_SWA, AuthMethod.APIM):
        response = await call_next(request)
        return response

    # Future: Azure AD, etc.
    # Unknown auth method
    return Response(
        content='{"detail":"Authentication method not implemented"}',
        status_code=501,
        media_type="application/json",
    )


# JWT Login Endpoint


@api.post("/api/v1/auth/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """
    OAuth 2.0 password flow login endpoint.

    Accepts username and password, returns JWT access token.

    Returns:
        {
          "access_token": "eyJ...",
          "token_type": "bearer"
        }
    """
    # Verify credentials against test users
    test_users = get_jwt_test_users()
    if not verify_test_user(form_data.username, form_data.password, test_users):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Create JWT access token
    secret_key = get_jwt_secret_key()
    algorithm = get_jwt_algorithm()
    expiration_minutes = get_jwt_expiration_minutes()

    access_token = create_access_token(
        data={"sub": form_data.username},
        secret_key=secret_key,
        algorithm=algorithm,
        expires_delta=timedelta(minutes=expiration_minutes),
    )

    return {"access_token": access_token, "token_type": "bearer"}


# Custom OpenAPI schema with security configuration
def custom_openapi():
    """
    Custom OpenAPI schema generator that adds security configuration when JWT auth is enabled.
    """
    if api.openapi_schema:
        return api.openapi_schema

    openapi_schema = get_openapi(
        title=api.title,
        version=api.version,
        description=api.description,
        routes=api.routes,
    )

    # Add security scheme when JWT auth is enabled
    auth_method = get_auth_method()
    if auth_method == AuthMethod.JWT:
        openapi_schema["components"]["securitySchemes"] = {
            "OAuth2PasswordBearer": {
                "type": "oauth2",
                "flows": {"password": {"tokenUrl": "/api/v1/auth/login", "scopes": {}}},
            }
        }
        # Apply security to all endpoints
        openapi_schema["security"] = [{"OAuth2PasswordBearer": []}]

    api.openapi_schema = openapi_schema
    return api.openapi_schema


# Override default OpenAPI function
api.openapi = custom_openapi


# Protected documentation endpoints
@api.get("/api/v1/docs", include_in_schema=False)
async def custom_swagger_ui_html(current_user: str = Depends(get_current_user)):
    """Protected Swagger UI documentation."""
    return get_swagger_ui_html(
        openapi_url="/api/v1/openapi.json",
        title=f"{api.title} - Swagger UI",
        oauth2_redirect_url="/api/v1/docs/oauth2-redirect",
    )


@api.get("/api/v1/redoc", include_in_schema=False)
async def custom_redoc_html(current_user: str = Depends(get_current_user)):
    """Protected ReDoc documentation."""
    return get_redoc_html(
        openapi_url="/api/v1/openapi.json", title=f"{api.title} - ReDoc"
    )


@api.get("/api/v1/openapi.json", include_in_schema=False)
async def get_open_api_endpoint(current_user: str = Depends(get_current_user)):
    """Protected OpenAPI schema."""
    return api.openapi()


# RFC1918 Private Address Ranges
RFC1918_RANGES = [
    ip_network("10.0.0.0/8"),
    ip_network("172.16.0.0/12"),
    ip_network("192.168.0.0/16"),
]

# RFC6598 Shared Address Space
RFC6598_RANGE = ip_network("100.64.0.0/10")

# Cloudflare IPv4 Ranges
CLOUDFLARE_IPV4_RANGES = [
    ip_network("173.245.48.0/20"),
    ip_network("103.21.244.0/22"),
    ip_network("103.22.200.0/22"),
    ip_network("103.31.4.0/22"),
    ip_network("141.101.64.0/18"),
    ip_network("108.162.192.0/18"),
    ip_network("190.93.240.0/20"),
    ip_network("188.114.96.0/20"),
    ip_network("197.234.240.0/22"),
    ip_network("198.41.128.0/17"),
    ip_network("162.158.0.0/15"),
    ip_network("104.16.0.0/13"),
    ip_network("104.24.0.0/14"),
    ip_network("172.64.0.0/13"),
    ip_network("131.0.72.0/22"),
]

# Cloudflare IPv6 Ranges
CLOUDFLARE_IPV6_RANGES = [
    ip_network("2400:cb00::/32"),
    ip_network("2606:4700::/32"),
    ip_network("2803:f800::/32"),
    ip_network("2405:b500::/32"),
    ip_network("2405:8100::/32"),
    ip_network("2a06:98c0::/29"),
    ip_network("2c0f:f248::/32"),
]


@api.get("/api/v1/health")
async def health_check():
    """
    Health check endpoint - always unauthenticated for operational use.

    Used by:
    - Container healthchecks (Docker/Kubernetes)
    - Load balancers
    - Monitoring systems (Prometheus, Datadog, etc.)
    """
    return {"status": "healthy", "service": "Subnet Calculator API (Azure Function)", "version": "1.0.0"}


@api.post("/api/v1/ipv4/validate")
async def validate_ipv4(
    request: ValidateRequest, current_user: str = Depends(get_current_user)
):
    """
    Validate if an IPv4/IPv6 address or CIDR range is well-formed.

    Returns validation result with type (address or network) and details.
    """
    address_str = request.address

    # Check if it's CIDR notation (contains /)
    if "/" in address_str:
        # Parse as network
        try:
            network = ip_network(address_str, strict=False)
            return {
                "valid": True,
                "type": "network",
                "address": address_str,
                "network_address": str(network.network_address),
                "netmask": str(network.netmask),
                "prefix_length": network.prefixlen,
                "num_addresses": network.num_addresses,
                "is_ipv4": isinstance(network, IPv4Network),
                "is_ipv6": isinstance(network, IPv6Network),
            }
        except (AddressValueError, NetmaskValueError, ValueError):
            raise HTTPException(status_code=400, detail="Invalid IP network format")
    else:
        # Parse as individual address
        try:
            addr = ip_address(address_str)
            return {
                "valid": True,
                "type": "address",
                "address": str(addr),
                "is_ipv4": isinstance(addr, IPv4Address),
                "is_ipv6": isinstance(addr, IPv6Address),
            }
        except (AddressValueError, ValueError):
            raise HTTPException(status_code=400, detail="Invalid IP address format")


@api.post("/api/v1/ipv4/check-private")
async def check_private(
    request: ValidateRequest, current_user: str = Depends(get_current_user)
):
    """
    Check if an IPv4 address or range is RFC1918 (private) or RFC6598 (shared).

    RFC1918 ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
    RFC6598 range: 100.64.0.0/10 (shared address space)
    """
    address_str = request.address

    # Parse as network or address
    try:
        # Try network first
        try:
            ip_obj = ip_network(address_str, strict=False)
        except (AddressValueError, NetmaskValueError, ValueError):
            ip_obj = ip_address(address_str)

        # Only process IPv4
        if isinstance(ip_obj, (IPv6Address, IPv6Network)):
            raise HTTPException(
                status_code=400, detail="This endpoint only supports IPv4 addresses"
            )

        # Check RFC1918
        is_rfc1918 = False
        matched_rfc1918 = None
        for rfc1918_range in RFC1918_RANGES:
            if isinstance(ip_obj, IPv4Network):
                if ip_obj.subnet_of(rfc1918_range) or ip_obj.supernet_of(rfc1918_range):
                    is_rfc1918 = True
                    matched_rfc1918 = str(rfc1918_range)
                    break
            else:  # IPv4Address
                if ip_obj in rfc1918_range:
                    is_rfc1918 = True
                    matched_rfc1918 = str(rfc1918_range)
                    break

        # Check RFC6598
        is_rfc6598 = False
        if isinstance(ip_obj, IPv4Network):
            is_rfc6598 = ip_obj.subnet_of(RFC6598_RANGE) or ip_obj.supernet_of(
                RFC6598_RANGE
            )
        else:  # IPv4Address
            is_rfc6598 = ip_obj in RFC6598_RANGE

        response = {
            "address": address_str,
            "is_rfc1918": is_rfc1918,
            "is_rfc6598": is_rfc6598,
        }

        if matched_rfc1918:
            response["matched_rfc1918_range"] = matched_rfc1918

        if is_rfc6598:
            response["matched_rfc6598_range"] = str(RFC6598_RANGE)

        return response

    except (AddressValueError, NetmaskValueError, ValueError) as e:
        raise HTTPException(
            status_code=400, detail=f"Invalid IP address or network: {str(e)}"
        )


@api.post("/api/v1/ipv4/check-cloudflare")
async def check_cloudflare(
    request: ValidateRequest, current_user: str = Depends(get_current_user)
):
    """
    Check if an IP address or range is within Cloudflare's IPv4 or IPv6 ranges.

    Returns matched Cloudflare ranges and IP version.
    """
    address_str = request.address

    # Parse as network or address
    try:
        # Try network first
        try:
            ip_obj = ip_network(address_str, strict=False)
        except (AddressValueError, NetmaskValueError, ValueError):
            ip_obj = ip_address(address_str)

        # Determine which Cloudflare ranges to check
        if isinstance(ip_obj, (IPv4Address, IPv4Network)):
            cloudflare_ranges = CLOUDFLARE_IPV4_RANGES
            ip_version = 4
        else:
            cloudflare_ranges = CLOUDFLARE_IPV6_RANGES
            ip_version = 6

        # Check against Cloudflare ranges
        matched_ranges = []
        for cf_range in cloudflare_ranges:
            if isinstance(ip_obj, (IPv4Network, IPv6Network)):
                # For networks, check if it's a subnet or supernet
                if ip_obj.subnet_of(cf_range) or ip_obj.supernet_of(cf_range):
                    matched_ranges.append(str(cf_range))
            else:  # Address
                if ip_obj in cf_range:
                    matched_ranges.append(str(cf_range))

        response = {
            "address": address_str,
            "is_cloudflare": len(matched_ranges) > 0,
            "ip_version": ip_version,
        }

        if matched_ranges:
            response["matched_ranges"] = matched_ranges

        return response

    except (AddressValueError, NetmaskValueError, ValueError) as e:
        raise HTTPException(
            status_code=400, detail=f"Invalid IP address or network: {str(e)}"
        )


@api.post("/api/v1/ipv4/subnet-info")
async def subnet_info(
    request: SubnetInfoRequest, current_user: str = Depends(get_current_user)
):
    """
    Calculate subnet information including usable IP ranges.

    Cloud provider IP reservations:
    - Azure/AWS: Reserve 5 IPs (.0, .1, .2, .3, and broadcast)
    - OCI: Reserve 3 IPs (.0, .1, and broadcast)
    - Standard: Reserve 2 IPs (.0 and broadcast)
    - /31 and /32: No reservations (point-to-point and host routes)
    """
    network_str = request.network
    mode = request.mode

    # Validate mode
    valid_modes = ["Azure", "AWS", "OCI", "Standard"]
    if mode not in valid_modes:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode '{mode}'. Must be one of: {', '.join(valid_modes)}",
        )

    # Parse network
    try:
        network = ip_network(network_str, strict=False)
    except (AddressValueError, NetmaskValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid network format: {str(e)}")

    # Only support IPv4 for now
    if not isinstance(network, IPv4Network):
        raise HTTPException(
            status_code=400,
            detail="This endpoint currently only supports IPv4 networks",
        )

    prefix_len = network.prefixlen
    total_addresses = network.num_addresses

    # Calculate usable IPs based on mode and prefix length
    if prefix_len < 31:
        # Standard subnets have network and broadcast addresses
        # Calculate first usable based on mode
        if mode in ["Azure", "AWS"]:
            first_usable_offset = 4  # Skip .0, .1, .2, .3
        elif mode == "OCI":
            first_usable_offset = 2  # Skip .0, .1
        else:  # Standard
            first_usable_offset = 1  # Skip .0

        first_usable_ip = str(network.network_address + first_usable_offset)
        last_usable_ip = str(network.broadcast_address - 1)  # Skip broadcast

        # Calculate usable addresses
        reserved_at_start = first_usable_offset
        reserved_at_end = 1  # broadcast
        usable_addresses = total_addresses - reserved_at_start - reserved_at_end

        response = {
            "network": network_str,
            "mode": mode,
            "network_address": str(network.network_address),
            "broadcast_address": str(network.broadcast_address),
            "netmask": str(network.netmask),
            "wildcard_mask": str(network.hostmask),
            "prefix_length": prefix_len,
            "total_addresses": total_addresses,
            "usable_addresses": usable_addresses,
            "first_usable_ip": first_usable_ip,
            "last_usable_ip": last_usable_ip,
        }
    else:
        # /31 (point-to-point) or /32 (host route) - no reservations
        if prefix_len == 31:
            # RFC 3021 - /31 point-to-point links
            first_usable_ip = str(network.network_address)
            last_usable_ip = str(network.network_address + 1)
            usable_addresses = 2

            response = {
                "network": network_str,
                "mode": mode,
                "network_address": str(network.network_address),
                "broadcast_address": None,
                "netmask": str(network.netmask),
                "wildcard_mask": str(network.hostmask),
                "prefix_length": prefix_len,
                "total_addresses": total_addresses,
                "usable_addresses": usable_addresses,
                "first_usable_ip": first_usable_ip,
                "last_usable_ip": last_usable_ip,
                "note": "RFC 3021 point-to-point link (no broadcast)",
            }
        else:  # /32
            # Single host
            host_ip = str(network.network_address)

            response = {
                "network": network_str,
                "mode": mode,
                "network_address": host_ip,
                "broadcast_address": None,
                "netmask": str(network.netmask),
                "wildcard_mask": str(network.hostmask),
                "prefix_length": prefix_len,
                "total_addresses": 1,
                "usable_addresses": 1,
                "first_usable_ip": host_ip,
                "last_usable_ip": host_ip,
                "note": "Single host address",
            }

    return response


# Create the main Azure Function
app = func.FunctionApp()


@app.function_name(name="HttpTrigger")
@app.route(route="{*route}", auth_level=func.AuthLevel.ANONYMOUS)
async def http_trigger(
    req: func.HttpRequest, context: func.Context
) -> func.HttpResponse:
    """Azure Function wrapper that forwards all requests to FastAPI via ASGI middleware"""
    return await func.AsgiMiddleware(api).handle_async(req, context)
