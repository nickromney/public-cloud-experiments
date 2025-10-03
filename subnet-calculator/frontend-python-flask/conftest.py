import pytest
from playwright.sync_api import Page
import threading
import time
from app import app


@pytest.fixture(scope="session")
def flask_server():
    """Start Flask server in a background thread for testing"""
    def run_server():
        app.run(host='127.0.0.1', port=5001, debug=False, use_reloader=False)

    thread = threading.Thread(target=run_server, daemon=True)
    thread.start()
    time.sleep(2)  # Give server time to start
    yield 'http://127.0.0.1:5001'


@pytest.fixture
def base_url(flask_server):
    """Provide base URL for tests"""
    return flask_server
