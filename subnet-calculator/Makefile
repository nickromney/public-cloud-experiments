.PHONY: help start-func-api start-stack4 start-stack5 dev

help:
	@echo "Subnet Calculator - Development Commands"
	@echo ""
	@echo "Quick Start:"
	@echo "  make dev                  Start everything (all stacks via podman-compose)"
	@echo "  make start-stack4         Start Stack 4 (TypeScript + Azure Function - No Auth)"
	@echo "  make start-stack5         Start Stack 5 (TypeScript + Azure Function - JWT Auth)"
	@echo ""
	@echo "Individual Services:"
	@echo "  make start-func-api       Start Azure Function API only (port 7071)"
	@echo ""

# Start Azure Function API using uv
start-func-api:
	@echo "Starting Azure Function API on port 7071..."
	cd api-fastapi-azure-function && uv run func start

# Start everything with podman-compose
dev:
	@echo "Starting all stacks with podman-compose..."
	@echo "Stack 1 (Flask + Azure Function):     http://localhost:8000"
	@echo "Stack 2 (Static HTML + Container App): http://localhost:8001"
	@echo "Stack 3 (Flask + Container App):       http://localhost:8002"
	@echo "Stack 4 (TypeScript + Container App):  http://localhost:3000"
	@echo ""
	podman-compose up

# Start SWA CLI for stack 4 (no auth) - SWA manages both frontend and API
start-stack4:
	@echo "Starting Stack 4 (TypeScript + Azure Function API - No Auth)..."
	@echo "SWA CLI will manage both the frontend and API."
	@echo ""
	@cd api-fastapi-azure-function && \
		export VIRTUAL_ENV="$(PWD)/api-fastapi-azure-function/.venv" && \
		export PATH="$$VIRTUAL_ENV/bin:$$PATH" && \
		export AUTH_METHOD="none" && \
		cd .. && \
		swa start --config-name stack4-no-auth

# Start SWA CLI for stack 5 (JWT auth) - SWA manages both frontend and API
start-stack5:
	@echo "Starting Stack 5 (TypeScript + Azure Function API with JWT)..."
	@echo "SWA CLI will manage both the frontend and API."
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
