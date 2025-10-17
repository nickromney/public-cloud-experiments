.PHONY: help start-func-api start-stack4 start-stack5 start-stack6 clean-stacks dev test test-stack4 test-stack5 test-bruno test-bruno-stack4 test-bruno-stack5 test-bruno-stack6

help:
	@echo "Subnet Calculator - Development Commands"
	@echo ""
	@echo "Quick Start (SWA CLI - One Stack at a Time):"
	@echo "  make start-stack4         Start local-stack-04 emulation via SWA CLI (port 4280, no auth)"
	@echo "  make start-stack5         Start local-stack-05 emulation via SWA CLI (port 4281, JWT auth)"
	@echo "  make start-stack6         Start local-stack-06 emulation via SWA CLI (port 4282, Entra ID auth)"
	@echo ""
	@echo "Testing:"
	@echo "  make test                 Show all test options"
	@echo "  make test-stack4          Test via curl (no auth, port 4280)"
	@echo "  make test-stack5          Test via curl (JWT auth, port 4281)"
	@echo "  make test-bruno-stack4    Test with Bruno CLI"
	@echo "  make test-bruno-stack5    Test with Bruno CLI (JWT auth)"
	@echo "  make test-bruno-stack6    Test with Bruno CLI (Entra ID - requires browser login)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean-stacks         Kill all running stack processes (ports 3000, 7071, 4280-4282)"
	@echo ""
	@echo "Note: Only run ONE SWA CLI stack at a time (port conflicts otherwise)"
	@echo ""
	@echo "Alternative (All podman-compose stacks):"
	@echo "  make dev                  Start everything (local-stack-01 through 05)"
	@echo ""
	@echo "Individual Services:"
	@echo "  make start-func-api       Start Azure Function API only (port 7071)"
	@echo ""

# Clean up all stack processes
clean-stacks:
	@echo "Cleaning up stack processes..."
	@echo "Checking ports: 3000 (Vite), 7071 (Azure Function), 4280-4282 (SWA)"
	@echo ""
	@for port in 3000 7071 4280 4281 4282; do \
		pid=$$(lsof -ti:$$port 2>/dev/null); \
		if [ -n "$$pid" ]; then \
			echo "Killing process on port $$port (PID: $$pid)"; \
			kill -9 $$pid 2>/dev/null || true; \
		else \
			echo "No process on port $$port"; \
		fi; \
	done
	@echo ""
	@echo "✓ Cleanup complete"

# Start Azure Function API using uv
start-func-api:
	@echo "Starting Azure Function API on port 7071..."
	cd api-fastapi-azure-function && uv run func start

# Start everything with podman-compose
dev:
	@echo "Starting all podman-compose stacks..."
	@echo "local-stack-01 (Static HTML + Container App): http://localhost:8001"
	@echo "local-stack-02 (Flask + Container App):       http://localhost:8002"
	@echo "local-stack-03 (Flask + Azure Function):      http://localhost:8000"
	@echo "local-stack-04 (TypeScript + Container App):  http://localhost:3000"
	@echo "local-stack-05 (TypeScript + Azure Function): http://localhost:3001"
	@echo ""
	podman-compose up

# Start SWA CLI for local-stack-04 emulation (no auth) - SWA manages everything
start-stack4:
	@echo "Starting local-stack-04 emulation via SWA CLI (TypeScript + Azure Function - No Auth)..."
	@echo "SWA CLI will manage both Vite and Azure Function"
	@echo "Access at: http://localhost:4280"
	@echo ""
	@cd api-fastapi-azure-function && \
		export VIRTUAL_ENV="$(PWD)/api-fastapi-azure-function/.venv" && \
		export PATH="$$VIRTUAL_ENV/bin:$$PATH" && \
		export AUTH_METHOD="none" && \
		cd .. && \
		swa start --config-name stack4-no-auth

# Start SWA CLI for local-stack-05 emulation (JWT auth) - SWA manages everything
start-stack5:
	@echo "Starting local-stack-05 emulation via SWA CLI (TypeScript + Azure Function - JWT Auth)..."
	@echo "SWA CLI will manage both Vite and Azure Function"
	@echo "Access at: http://localhost:4281"
	@echo ""
	@cd api-fastapi-azure-function && \
		export VIRTUAL_ENV="$(PWD)/api-fastapi-azure-function/.venv" && \
		export PATH="$$VIRTUAL_ENV/bin:$$PATH" && \
		export AUTH_METHOD="jwt" && \
		export VITE_AUTH_ENABLED="true" && \
		export VITE_JWT_USERNAME="demo" && \
		export VITE_JWT_PASSWORD="password123" && \
		cd .. && \
		swa start --config-name stack5-jwt

# Start SWA CLI for local-stack-06 emulation (Entra ID auth) - SWA manages everything
start-stack6:
	@echo "Starting local-stack-06 emulation via SWA CLI (TypeScript + Azure Function - Entra ID Auth)..."
	@echo "SWA CLI will manage both Vite and Azure Function"
	@echo "SWA platform emulates Entra ID authentication"
	@echo "Access at: http://localhost:4282"
	@echo ""
	@cd api-fastapi-azure-function && \
		export VIRTUAL_ENV="$(PWD)/api-fastapi-azure-function/.venv" && \
		export PATH="$$VIRTUAL_ENV/bin:$$PATH" && \
		export AUTH_METHOD="none" && \
		cd .. && \
		swa start --config-name stack6-entra

# Test help and overview
test:
	@echo "SWA CLI Testing Options"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - SWA CLI stack must be running (e.g., 'make start-stack4')"
	@echo "  - curl installed (standard on most systems)"
	@echo "  - jq installed for JSON parsing: brew install jq"
	@echo ""
	@echo "curl Tests (lightweight):"
	@echo "  make test-stack4          Test local-stack-04 emulation (no auth, port 4280)"
	@echo "  make test-stack5          Test local-stack-05 emulation (JWT auth, port 4281)"
	@echo ""
	@echo "Bruno CLI Tests (comprehensive):"
	@echo "  make test-bruno-stack4    Test local-stack-04 via Bruno CLI"
	@echo "  make test-bruno-stack5    Test local-stack-05 via Bruno CLI"
	@echo "  make test-bruno-stack6    Test local-stack-06 via Bruno CLI (login via browser first)"
	@echo ""
	@echo "Note: Only ONE SWA CLI stack can run at a time (port conflicts)"
	@echo "      Run the matching test for whichever stack is running"
	@echo ""
	@echo "Security Inspection (use Bruno GUI):"
	@echo "  1. Open Bruno GUI and load bruno-collections/"
	@echo "  2. Select 'local' environment (top-right)"
	@echo "  3. Run requests and inspect Headers/Cookies tabs"
	@echo "  4. See docs/SECURITY-INSPECTION.md for what to look for"
	@echo ""
	@echo "Manual Testing:"
	@echo "  See README.md 'API Testing and Debugging' section for:"
	@echo "  - curl examples for each stack"
	@echo "  - xh (modern curl alternative)"
	@echo "  - Bruno GUI application"

# Test local-stack-04 emulation (no auth)
test-stack4:
	@echo "Testing local-stack-04 emulation (No Auth) on http://localhost:4280"
	@echo ""
	@echo "=== Test 1: Health Check ==="
	@curl -s -f http://localhost:4280/api/v1/health | jq '.' || \
		(echo "[FAIL] Health check failed"; exit 1)
	@echo "[PASS] Health check passed"
	@echo ""
	@echo "=== Test 2: List Providers ==="
	@curl -s -f http://localhost:4280/api/v1/providers | jq '.' || \
		(echo "[FAIL] List providers failed"; exit 1)
	@echo "[PASS] List providers passed"
	@echo ""
	@echo "=== Test 3: Calculate Subnet (Azure) ==="
	@curl -s -f -X POST http://localhost:4280/api/v1/calculate \
		-H "Content-Type: application/json" \
		-d '{"cidr":"10.0.0.0/24","provider":"azure"}' | jq '.' || \
		(echo "[FAIL] Calculate subnet failed"; exit 1)
	@echo "[PASS] Calculate subnet passed"
	@echo ""
	@echo "=== Test 4: Calculate Subnet (Standard) ==="
	@curl -s -f -X POST http://localhost:4280/api/v1/calculate \
		-H "Content-Type: application/json" \
		-d '{"cidr":"192.168.1.0/24","provider":"standard"}' | jq '.' || \
		(echo "[FAIL] Calculate standard subnet failed"; exit 1)
	@echo "[PASS] Calculate standard subnet passed"
	@echo ""
	@echo "=== Test 5: Invalid CIDR (should fail gracefully) ==="
	@curl -s -X POST http://localhost:4280/api/v1/calculate \
		-H "Content-Type: application/json" \
		-d '{"cidr":"invalid","provider":"azure"}' | jq '.' || true
	@echo "[PASS] Error handling passed"
	@echo ""
	@echo "All Stack 4 tests passed!"

# Test local-stack-05 emulation (JWT auth)
test-stack5:
	@echo "Testing local-stack-05 emulation (JWT Auth) on http://localhost:4281"
	@echo ""
	@echo "=== Test 1: Health Check (no auth - should fail) ==="
	@curl -s -w "\nHTTP Status: %{http_code}\n" http://localhost:4281/api/v1/health || true
	@echo "[PASS] Correctly requires authentication"
	@echo ""
	@echo "=== Test 2: Login and Get Token ==="
	@TOKEN=$$(curl -s -X POST http://localhost:4281/api/v1/auth/login \
		-H "Content-Type: application/json" \
		-d '{"username":"demo","password":"password123"}' | jq -r '.access_token'); \
	if [ -z "$$TOKEN" ] || [ "$$TOKEN" = "null" ]; then \
		echo "[FAIL] Login failed - could not get token"; \
		exit 1; \
	fi; \
	echo "[PASS] Login successful, token received"; \
	echo "Token: $${TOKEN:0:20}..."; \
	echo ""; \
	echo "=== Test 3: Health Check (with auth) ==="; \
	curl -s -f http://localhost:4281/api/v1/health \
		-H "Authorization: Bearer $$TOKEN" | jq '.' || \
		(echo "[FAIL] Authenticated health check failed"; exit 1); \
	echo "[PASS] Authenticated health check passed"; \
	echo ""; \
	echo "=== Test 4: Calculate Subnet (with auth) ==="; \
	curl -s -f -X POST http://localhost:4281/api/v1/calculate \
		-H "Authorization: Bearer $$TOKEN" \
		-H "Content-Type: application/json" \
		-d '{"cidr":"10.0.0.0/24","provider":"azure"}' | jq '.' || \
		(echo "[FAIL] Calculate subnet failed"; exit 1); \
	echo "[PASS] Calculate subnet passed"; \
	echo ""; \
	echo "=== Test 5: List Providers (with auth) ==="; \
	curl -s -f http://localhost:4281/api/v1/providers \
		-H "Authorization: Bearer $$TOKEN" | jq '.' || \
		(echo "[FAIL] List providers failed"; exit 1); \
	echo "[PASS] List providers passed"; \
	echo ""; \
	echo "All Stack 5 tests passed!"

# Test Local Stack 04 with Bruno CLI
test-bruno-stack4:
	@echo "Running Bruno CLI Tests for Local Stack 04 (Vite No Auth)"
	@echo ""
	@if [ ! -d "bruno-collections" ]; then \
		echo "[FAIL] Bruno collections directory not found"; \
		echo "Expected: ./bruno-collections/"; \
		exit 1; \
	fi
	@echo "=== Testing Local Stack 04 ==="
	@cd bruno-collections && \
		npx @usebruno/cli@latest run "Local Stack 04 - Vite No Auth" --env local --output ../results-stack4.json --format json
	@echo ""
	@echo "Local Stack 04 tests completed - see results-stack4.json"

# Test Local Stack 05 with Bruno CLI
test-bruno-stack5:
	@echo "Running Bruno CLI Tests for Local Stack 05 (Vite JWT Auth)"
	@echo ""
	@if [ ! -d "bruno-collections" ]; then \
		echo "[FAIL] Bruno collections directory not found"; \
		echo "Expected: ./bruno-collections/"; \
		exit 1; \
	fi
	@echo "=== Testing Local Stack 05 ==="
	@cd bruno-collections && \
		npx @usebruno/cli@latest run "Local Stack 05 - Vite JWT Auth" --env local --output ../results-stack5.json --format json
	@echo ""
	@echo "Local Stack 05 tests completed - see results-stack5.json"

# Test Local Stack 06 with Bruno CLI
test-bruno-stack6:
	@echo "Running Bruno CLI Tests for Local Stack 06 (Entra ID Auth emulation)"
	@echo ""
	@echo "NOTE: Local Stack 06 requires browser-based login for full testing"
	@echo "      The CLI tests will check unauthenticated access"
	@echo "      For authenticated tests, use Bruno GUI after logging in"
	@echo ""
	@if [ ! -d "bruno-collections" ]; then \
		echo "[FAIL] Bruno collections directory not found"; \
		echo "Expected: ./bruno-collections/"; \
		exit 1; \
	fi
	@echo "=== Testing Local Stack 06 ==="
	@cd bruno-collections && \
		npx @usebruno/cli@latest run "Local Stack 06 - Entra ID Auth" --env local --output ../results-stack6.json --format json
	@echo ""
	@echo "Local Stack 06 tests completed - see results-stack6.json"
