import os
from datetime import datetime, timedelta

import requests
from flask import Flask, jsonify, render_template, request, send_from_directory
from flask_session import Session

from auth import init_auth

app = Flask(__name__)

# Configure session
app.config["SECRET_KEY"] = os.getenv("FLASK_SECRET_KEY", "dev-key-change-in-production")
app.config["SESSION_TYPE"] = "filesystem"
app.config["SESSION_PERMANENT"] = False
app.config["SESSION_COOKIE_SECURE"] = os.getenv("FLASK_ENV", "development") == "production"
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

Session(app)

# Initialize Entra ID authentication (optional - only if env vars are set)
auth = init_auth(app)

# API base URL - configurable via environment variable
API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:7071/api/v1")

# Stack identifier for UI display
STACK_NAME = os.getenv("STACK_NAME", "Python Flask + Azure Function")

# JWT Authentication - optional (only used in Docker Compose)
JWT_USERNAME = os.getenv("JWT_USERNAME")
JWT_PASSWORD = os.getenv("JWT_PASSWORD")

# Token cache (in-memory, resets on restart)
_jwt_token = None
_jwt_token_expires = None


def get_jwt_token() -> str | None:
    """
    Get JWT token for API authentication.
    Returns None if JWT authentication is not configured.
    Caches token and refreshes when expired.
    """
    global _jwt_token, _jwt_token_expires

    # If JWT not configured, return None (no auth)
    if not JWT_USERNAME or not JWT_PASSWORD:
        return None

    # Check if we have a valid cached token
    if _jwt_token and _jwt_token_expires and datetime.now() < _jwt_token_expires:
        return _jwt_token

    # Login to get new token
    try:
        login_response = requests.post(
            f"{API_BASE_URL}/auth/login",
            data={"username": JWT_USERNAME, "password": JWT_PASSWORD},
            timeout=5,
        )
        login_response.raise_for_status()

        token_data = login_response.json()
        _jwt_token = token_data["access_token"]

        # Cache for 25 minutes (tokens expire in 30, refresh before that)
        _jwt_token_expires = datetime.now() + timedelta(minutes=25)

        return _jwt_token

    except requests.RequestException as e:
        print(f"JWT authentication failed: {e}")
        # Clear cached token on failure
        _jwt_token = None
        _jwt_token_expires = None
        raise


def get_auth_headers() -> dict:
    """
    Get authentication headers for API requests.
    Returns empty dict if no authentication configured.
    """
    token = get_jwt_token()
    if token:
        return {"Authorization": f"Bearer {token}"}
    return {}


def get_api_health() -> dict | None:
    """
    Get API health status.
    Returns health info dict or None if API is unavailable.
    """
    try:
        response = requests.get(
            f"{API_BASE_URL}/health",
            timeout=2,
        )
        response.raise_for_status()
        health_data = response.json()
        # Add the endpoint URL to the health data
        health_data["endpoint"] = f"{API_BASE_URL}/health"
        return health_data
    except requests.RequestException:
        return None


def perform_lookup(address: str, mode: str = "Standard") -> dict:
    """
    Perform IP address lookup against the API
    Raises requests.HTTPError for 4xx errors (bad input)
    Raises requests.RequestException for connection/server errors
    """
    results = {}

    try:
        # Get authentication headers (empty dict if no JWT configured)
        headers = get_auth_headers()

        # 1. Validate the address
        validate_response = requests.post(
            f"{API_BASE_URL}/ipv4/validate",
            json={"address": address},
            headers=headers,
            timeout=5,
        )
        validate_response.raise_for_status()
        results["validate"] = validate_response.json()

        # 2. Check if RFC1918 (private)
        private_response = requests.post(
            f"{API_BASE_URL}/ipv4/check-private",
            json={"address": address},
            headers=headers,
            timeout=5,
        )
        private_response.raise_for_status()
        results["private"] = private_response.json()

        # 3. Check if Cloudflare
        cloudflare_response = requests.post(
            f"{API_BASE_URL}/ipv4/check-cloudflare",
            json={"address": address},
            headers=headers,
            timeout=5,
        )
        cloudflare_response.raise_for_status()
        results["cloudflare"] = cloudflare_response.json()

        # 4. Get subnet info if it's a network
        if results["validate"].get("type") == "network":
            subnet_response = requests.post(
                f"{API_BASE_URL}/ipv4/subnet-info",
                json={"network": address, "mode": mode},
                headers=headers,
                timeout=5,
            )
            subnet_response.raise_for_status()
            results["subnet"] = subnet_response.json()

        return results

    except requests.HTTPError as e:
        # 4xx errors are client errors (bad input), not API unavailability
        if e.response is not None and 400 <= e.response.status_code < 500:
            # Try to extract error detail from API response
            try:
                error_detail = e.response.json().get("detail", str(e))
            except Exception:
                error_detail = str(e)
            raise ValueError(f"Invalid input: {error_detail}") from e
        # 5xx errors are server errors - treat as API down
        raise


@app.route("/favicon.svg")
def favicon_svg():
    """Serve favicon from static directory at root path"""
    return send_from_directory("static", "favicon.svg", mimetype="image/svg+xml")


@app.route("/favicon.ico")
def favicon_ico():
    """Fallback for browsers looking for .ico format"""
    # Redirect to .svg since we only have SVG
    return send_from_directory("static", "favicon.svg", mimetype="image/svg+xml")


@app.route("/", methods=["GET", "POST"])
def index():
    """Main page - handles both GET and traditional form POST (no-JS fallback)"""
    # Apply authentication if configured
    if auth and auth.is_authenticated() is False:
        return auth.login()

    # Get API health status for display
    api_health = get_api_health()
    # Get user info if authenticated
    user_info = auth.get_user() if auth else None

    if request.method == "POST":
        # Traditional form submission (no JavaScript)
        address = request.form.get("address", "").strip()
        mode = request.form.get("mode", "Standard")

        if not address:
            return render_template(
                "index.html", error="Address is required", stack_name=STACK_NAME, user_info=user_info
            )

        # Call lookup and render results on same page
        try:
            results = perform_lookup(address, mode)
            return render_template(
                "index.html",
                results=results,
                address=address,
                mode=mode,
                api_health=api_health,
                stack_name=STACK_NAME,
                user_info=user_info,
            )
        except ValueError as e:
            # Bad input (4xx error) - show validation error
            return render_template(
                "index.html",
                error=str(e),
                address=address,
                mode=mode,
                api_health=api_health,
                stack_name=STACK_NAME,
                user_info=user_info,
            )
        except requests.exceptions.RequestException as e:
            # API is down (connection error, timeout, 5xx) - suggest cidr.xyz
            cidr_url = f"https://cidr.xyz/#{address}"
            return render_template(
                "index.html",
                api_down=True,
                cidr_url=cidr_url,
                address=address,
                error=f"Backend API unavailable: {str(e)}",
                api_health=api_health,
                stack_name=STACK_NAME,
                user_info=user_info,
            )

    return render_template("index.html", api_health=api_health, stack_name=STACK_NAME, user_info=user_info)


@app.route("/lookup", methods=["POST"])
def lookup():
    """AJAX endpoint for IP address lookup"""
    data = request.get_json()
    address = data.get("address")
    mode = data.get("mode", "Standard")

    if not address:
        return jsonify({"error": "Address is required"}), 400

    try:
        results = perform_lookup(address, mode)
        return jsonify(results)

    except ValueError as e:
        # Bad input (4xx error) - return validation error
        return jsonify({"error": str(e)}), 400
    except requests.exceptions.RequestException as e:
        # API is down (connection error, timeout, 5xx) - return error with cidr.xyz suggestion
        cidr_url = f"https://cidr.xyz/#{address}"
        return (
            jsonify(
                {
                    "error": f"Backend API unavailable: {str(e)}",
                    "cidr_url": cidr_url,
                    "api_down": True,
                }
            ),
            503,
        )
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500


if __name__ == "__main__":
    app.run(debug=True)
