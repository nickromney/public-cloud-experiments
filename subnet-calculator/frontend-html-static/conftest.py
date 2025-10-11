"""Shared pytest fixtures for frontend testing."""

import pytest


@pytest.fixture(scope="session")
def base_url():
    """Base URL for the frontend application."""
    return "http://localhost:8001"
