.PHONY: help clean-ports \
  start-direct-azure-function start-direct-container-app start-direct-flask start-direct-vite \
  start-direct-all-bg wait-direct-services \
  start-compose-all start-compose-01 start-compose-02 start-compose-03 start-compose-04 \
  start-swa-04 start-swa-05 start-swa-06 \
  test-bruno-direct test-bruno-compose test-bruno-swa \
  test-bruno-direct-full test-bruno-compose-full test-bruno-swa-full

help:
	@echo "Subnet Calculator - Development Commands"
	@echo ""
	@echo "=== Direct Launches (7000s) ==="
	@echo "  make start-direct-azure-function    Start Azure Function API (port 7071)"
	@echo "  make start-direct-container-app     Start Container App API (port 7080)"
	@echo "  make start-direct-flask             Start Flask frontend (port 7000)"
	@echo "  make start-direct-vite              Start TypeScript Vite frontend (port 7010)"
	@echo ""
	@echo "=== Podman-Compose (8000s) ==="
	@echo "  make start-compose-all              Start all compose stacks (8000-8003)"
	@echo "  make start-compose-01               Start compose-01: Flask + Azure Function (8000)"
	@echo "  make start-compose-02               Start compose-02: Static HTML + Container App (8001)"
	@echo "  make start-compose-03               Start compose-03: Flask + Container App (8002)"
	@echo "  make start-compose-04               Start compose-04: TypeScript Vite + Container App (8003)"
	@echo ""
	@echo "=== SWA CLI (4000s) ==="
	@echo "  make start-swa-04                   Start SWA 04: No Auth (port 4280)"
	@echo "  make start-swa-05                   Start SWA 05: JWT Auth (port 4281)"
	@echo "  make start-swa-06                   Start SWA 06: Entra ID Auth (port 4282)"
	@echo ""
	@echo "=== Testing ==="
	@echo "  make test-bruno-direct              Test direct launches with Bruno CLI"
	@echo "  make test-bruno-direct-full         Start direct services + test + cleanup"
	@echo "  make test-bruno-compose             Test compose stacks with Bruno CLI"
	@echo "  make test-bruno-compose-full        Start compose services + test + cleanup"
	@echo "  make test-bruno-swa                 Test SWA stacks with Bruno CLI"
	@echo "  make test-bruno-swa-full            Start SWA services + test + cleanup"
	@echo ""
	@echo "=== Cleanup ==="
	@echo "  make clean-ports                    Kill all processes on used ports"
	@echo ""

# Clean up all ports
clean-ports:
	@echo "Cleaning up all ports (7000s, 8000s, 4000s)..."
	@for port in 7071 7080 7000 7010 8000 8001 8002 8003 8080 8090 4280 4281 4282; do \
		pid=$$(lsof -ti:$$port 2>/dev/null); \
		if [ -n "$$pid" ]; then \
			echo "  Killing process on port $$port (PID: $$pid)"; \
			kill -9 $$pid 2>/dev/null || true; \
		fi; \
	done
	@echo "✓ Cleanup complete"

##@ Direct Launches

start-direct-azure-function:
	@echo "Starting Azure Function API (port 7071)..."
	cd api-fastapi-azure-function && \
		export AUTH_METHOD=jwt && \
		uv run func start

start-direct-container-app:
	@echo "Starting Container App API (port 7080)..."
	cd api-fastapi-container-app && \
		uv run uvicorn app.main:app --reload --port 7080

start-direct-flask:
	@echo "Starting Flask frontend (port 7000)..."
	cd frontend-python-flask && \
		export API_URL=http://localhost:7071 && \
		uv run flask run --port 7000

start-direct-vite:
	@echo "Starting TypeScript Vite frontend (port 7010)..."
	cd frontend-typescript-vite && \
		VITE_API_URL=http://localhost:7080 npm run dev -- --port 7010

# Background service startup helpers
start-direct-all-bg:
	@echo "Starting all direct services in background..."
	@mkdir -p /tmp/subnet-calc-logs
	@(cd api-fastapi-azure-function && export AUTH_METHOD=jwt && uv run func start) > /tmp/subnet-calc-logs/azure-func.log 2>&1 &
	@(cd api-fastapi-container-app && uv run uvicorn app.main:app --reload --port 7080) > /tmp/subnet-calc-logs/container-app.log 2>&1 &
	@(cd frontend-python-flask && export API_URL=http://localhost:7071 && uv run flask run --port 7000) > /tmp/subnet-calc-logs/flask.log 2>&1 &
	@(cd frontend-typescript-vite && VITE_API_URL=http://localhost:7080 npm run dev -- --port 7010) > /tmp/subnet-calc-logs/vite.log 2>&1 &
	@echo "✓ Services started in background"
	@echo "  Logs available in /tmp/subnet-calc-logs/"

wait-direct-services:
	@echo "Waiting for direct services to be ready..."
	@for service in "Azure Function:7071" "Container App:7080"; do \
		name=$${service%:*}; \
		port=$${service#*:}; \
		echo "Checking $$name (port $$port)..."; \
		success=false; \
		for i in 1 2 3 4 5; do \
			if curl -s http://localhost:$$port/api/v1/health > /dev/null 2>&1; then \
				echo "✓ $$name is ready"; \
				success=true; \
				break; \
			fi; \
			if [ $$i -lt 5 ]; then \
				echo "  Attempt $$i/5, waiting..."; \
				sleep 2; \
			fi; \
		done; \
		if [ "$$success" = "false" ]; then \
			echo "✗ $$name failed to become ready"; \
			exit 1; \
		fi; \
	done
	@echo "✓ All direct services are ready!"

##@ Podman-Compose

start-compose-all:
	@echo "Starting all podman-compose stacks..."
	@echo "  compose-01 (Flask + Azure Function):           http://localhost:8000"
	@echo "  compose-02 (Static HTML + Container App):      http://localhost:8001"
	@echo "  compose-03 (Flask + Container App):            http://localhost:8002"
	@echo "  compose-04 (TypeScript Vite + Container App):  http://localhost:8003"
	podman-compose up

start-compose-01:
	@echo "Starting compose-01: Flask + Azure Function (port 8000)..."
	podman-compose up frontend-python-flask api-fastapi-azure-function

start-compose-02:
	@echo "Starting compose-02: Static HTML + Container App (port 8001)..."
	podman-compose up frontend-html-static api-fastapi-container-app

start-compose-03:
	@echo "Starting compose-03: Flask + Container App (port 8002)..."
	podman-compose up frontend-python-flask-container-app api-fastapi-container-app

start-compose-04:
	@echo "Starting compose-04: TypeScript Vite + Container App (port 8003)..."
	podman-compose up frontend-typescript-vite api-fastapi-container-app

##@ SWA CLI

start-swa-04:
	@echo "Starting SWA 04: TypeScript Vite + Container App - No Auth (port 4280)..."
	swa start --config-name swa-04

start-swa-05:
	@echo "Starting SWA 05: TypeScript Vite + Azure Function - JWT Auth (port 4281)..."
	export AUTH_METHOD=jwt && \
	export VITE_AUTH_ENABLED=true && \
	swa start --config-name swa-05

start-swa-06:
	@echo "Starting SWA 06: TypeScript Vite + Azure Function - Entra ID (port 4282)..."
	export AUTH_METHOD=none && \
	swa start --config-name swa-06

##@ Testing

test-bruno-direct:
	@echo "Testing direct launches with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run direct-azure-function --env local && \
		npx @usebruno/cli@latest run direct-container-app --env local

test-bruno-compose:
	@echo "Testing compose stacks with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run compose-01 --env local && \
		npx @usebruno/cli@latest run compose-02 --env local && \
		npx @usebruno/cli@latest run compose-03 --env local && \
		npx @usebruno/cli@latest run compose-04 --env local

test-bruno-swa:
	@echo "Testing SWA stacks with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run swa-04 --env local && \
		npx @usebruno/cli@latest run swa-05 --env local && \
		npx @usebruno/cli@latest run swa-06 --env local

##@ Full Test Chains (Start + Test + Cleanup)

test-bruno-direct-full: clean-ports start-direct-all-bg wait-direct-services test-bruno-direct clean-ports
	@echo ""
	@echo "✓ Direct testing complete (services cleaned up)"

test-bruno-compose-full:
	@echo "Starting compose services..."
	podman-compose up -d
	@echo "Waiting for compose services to be ready..."
	@sleep 10
	@echo "Running compose tests..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run compose-01 --env local && \
		npx @usebruno/cli@latest run compose-02 --env local && \
		npx @usebruno/cli@latest run compose-03 --env local && \
		npx @usebruno/cli@latest run compose-04 --env local
	@echo "Stopping compose services..."
	podman-compose down
	@echo "✓ Compose testing complete"

test-bruno-swa-full:
	@echo "Starting SWA services..."
	@mkdir -p /tmp/subnet-calc-logs
	@(swa start --config-name swa-04) > /tmp/subnet-calc-logs/swa-04.log 2>&1 &
	@echo "$$!" > /tmp/swa-04.pid
	@(export AUTH_METHOD=jwt && export VITE_AUTH_ENABLED=true && swa start --config-name swa-05) > /tmp/subnet-calc-logs/swa-05.log 2>&1 &
	@echo "$$!" > /tmp/swa-05.pid
	@(export AUTH_METHOD=none && swa start --config-name swa-06) > /tmp/subnet-calc-logs/swa-06.log 2>&1 &
	@echo "$$!" > /tmp/swa-06.pid
	@echo "Waiting for SWA services to be ready..."
	@sleep 15
	@echo "Running SWA tests..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run swa-04 --env local || true; \
		npx @usebruno/cli@latest run swa-05 --env local || true; \
		npx @usebruno/cli@latest run swa-06 --env local || true
	@echo "Stopping SWA services..."
	@kill $$(cat /tmp/swa-04.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-05.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-06.pid 2>/dev/null) 2>/dev/null || true
	@sleep 2
	@echo "✓ SWA testing complete"
