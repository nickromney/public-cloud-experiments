"""Tests for main FastAPI application routes."""

import pytest
from fastapi.testclient import TestClient
from app.main import app


@pytest.fixture
def client():
    """Create test client with no authentication."""
    return TestClient(app)


def test_root_endpoint(client):
    """Test root endpoint returns API information."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Subnet Calculator API"
    assert data["version"] == "1.0.0"
    assert data["docs"] == "/docs"
    assert data["openapi"] == "/openapi.json"
    assert data["health"] == "/health"


def test_health_endpoint(client):
    """Test health endpoint is accessible without auth."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_health_ready_endpoint(client):
    """Test health/ready endpoint."""
    response = client.get("/health/ready")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


def test_health_live_endpoint(client):
    """Test health/live endpoint."""
    response = client.get("/health/live")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"


def test_docs_accessible(client):
    """Test Swagger UI is accessible."""
    response = client.get("/docs")
    assert response.status_code == 200
    assert b"Swagger UI" in response.content or b"swagger" in response.content


def test_redoc_accessible(client):
    """Test ReDoc is accessible."""
    response = client.get("/redoc")
    assert response.status_code == 200


def test_openapi_schema_accessible(client):
    """Test OpenAPI schema is accessible."""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    assert schema["info"]["title"] == "Subnet Calculator API"
    assert schema["info"]["version"] == "1.0.0"
    assert "/subnets/ipv4" in schema["paths"]
    assert "/subnets/ipv6" in schema["paths"]
    assert "/subnets/validate" in schema["paths"]
    assert "/subnets/check-private" in schema["paths"]
    assert "/subnets/check-cloudflare" in schema["paths"]
