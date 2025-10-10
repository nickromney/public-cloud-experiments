# public-cloud-experiments

Investigations into various cloud technologies, typically on Azure, with some AWS

## Projects

### Subnet Calculator

A full-stack IPv4/IPv6 subnet calculator with multiple backend and frontend implementations demonstrating different architectural patterns.

**Architecture:**

- **2 Backend APIs**: Azure Function (with JWT auth) and Container App (no auth)
- **4 Frontend Options**: Flask (server-side), Static HTML (client-side), TypeScript Vite (modern SPA)
- **4 Complete Stacks**: Mix and match backends with frontends

**Quick Start (All Stacks):**

```bash
cd subnet-calculator
podman-compose up -d

# Stack 1 - Flask + Azure Function:        http://localhost:8000
# Stack 2 - Static HTML + Container App:   http://localhost:8001
# Stack 3 - Flask + Container App:         http://localhost:8002
# Stack 4 - TypeScript Vite + Container App: http://localhost:3000
```

**Quick Start (Single Stack):**

```bash
# Stack 4 - Modern TypeScript SPA (recommended)
podman-compose up api-fastapi-container-app frontend-typescript-vite
# Access at http://localhost:3000
```

**Features:**

- IPv4/IPv6 address validation and CIDR notation support
- RFC1918/RFC6598 private address detection
- Cloudflare IP range detection
- Cloud provider-specific subnet calculations (Azure, AWS, OCI, Standard)
- Modern responsive web UI with dark/light mode
- Interactive Swagger UI API documentation
- Comprehensive test coverage (188 tests across all components)
- Security scanning with Trivy (4/5 images have 0 vulnerabilities)

See [subnet-calculator/README.md](subnet-calculator/README.md) for details.

### Infrastructure as Code Experiments

- **Claranet tfwrapper**: Wrapper tool for managing OpenTofu/Terraform stacks
- **Terragrunt**: DRY Terraform configurations with hierarchical management

## Repository Structure

```text
.
├── .github/                       # GitHub Actions workflows
├── .gitleaks.toml                 # Gitleaks secret scanning config
├── .pre-commit-config.yaml        # Pre-commit hooks
├── .gitignore
├── README.md
├── subnet-calculator/                # IPv4/IPv6 subnet calculator
│   ├── compose.yml                   # Docker/Podman Compose (all 6 services)
│   ├── README.md                     # Project documentation
│   ├── api-fastapi-azure-function/   # Backend API 1 (Azure Function + JWT)
│   │   ├── function_app.py           # FastAPI app with validation
│   │   ├── auth.py                   # JWT authentication
│   │   ├── test_*.py                 # pytest test suite (108 tests)
│   │   ├── Dockerfile                # Azure Functions Python 3.11 runtime
│   │   └── README.md
│   ├── api-fastapi-container-app/    # Backend API 2 (Container App)
│   │   ├── app/main.py               # FastAPI app (Uvicorn)
│   │   ├── app/auth.py               # Optional JWT/Entra ID auth
│   │   ├── tests/test_*.py           # pytest test suite (60 tests)
│   │   ├── Dockerfile                # Python 3.11 slim container
│   │   └── README.md
│   ├── frontend-python-flask/        # Frontend 1 (Flask + Pico CSS)
│   │   ├── app.py                    # Flask application
│   │   ├── templates/                # Jinja2 templates
│   │   ├── test_frontend.py          # pytest tests (20 tests)
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── frontend-html-static/         # Frontend 2 (Static HTML + JS)
│   │   ├── index.html                # HTML + Pico CSS
│   │   ├── js/app.js                 # Vanilla JavaScript
│   │   ├── Dockerfile                # nginx Alpine
│   │   └── README.md
│   └── frontend-typescript-vite/     # Frontend 3 (TypeScript SPA)
│       ├── src/main.ts               # TypeScript application
│       ├── tests/frontend.spec.ts    # Playwright E2E tests
│       ├── Dockerfile                # Multi-stage nginx build
│       ├── package.json              # Node dependencies
│       └── README.md
└── terraform/
    ├── claranet-tfwrapper/        # Claranet tfwrapper experiment
    │   ├── .gitignore
    │   ├── Makefile               # Simplified commands
    │   ├── README.md              # Detailed documentation
    │   ├── setup-env.sh
    │   ├── generate-state-config.sh
    │   ├── conf/                  # Stack configurations
    │   └── templates/             # Stack templates
    │       └── azure/
    │           ├── basic/         # Basic App Service Plan
    │           └── platform/      # Full platform with Function App
    ├── terragrunt/                # Terragrunt experiment
    │   ├── README.md
    │   ├── Makefile
    │   ├── root.hcl               # Root configuration
    │   └── _envcommon/            # Shared configurations
    └── modules/                   # Reusable Terraform modules
```

## Quick Start

### Running Subnet Calculator

**All stacks:**

```bash
cd subnet-calculator
podman-compose up -d
```

Access all stacks:

- Stack 1 (Flask + Azure Function): <http://localhost:8000>
- Stack 2 (Static HTML + Container App): <http://localhost:8001>
- Stack 3 (Flask + Container App): <http://localhost:8002>
- Stack 4 (TypeScript Vite + Container App): <http://localhost:3000>

**Single stack (Stack 4 - recommended):**

```bash
cd subnet-calculator
podman-compose up api-fastapi-container-app frontend-typescript-vite
```

Access at <http://localhost:3000> and API docs at <http://localhost:8090/api/v1/docs>.

### Terraform Experiments

**Claranet tfwrapper:**

```bash
cd terraform/claranet-tfwrapper
source ./setup-env.sh
make platform plan dev uks
```

See [terraform/claranet-tfwrapper/README.md](terraform/claranet-tfwrapper/README.md) for details.

## Excluded from Git

- `terraform/reference/` - Cloned Claranet module repositories for reference
- `terraform/claranet-tfwrapper/.run/` - tfwrapper's Azure CLI cache
- `**/.terraform/` - Terraform/OpenTofu provider cache
- `**/.terragrunt-cache/` - Terragrunt cache
- `*.tfstate*` - State files
- `*.tfvars` - Variable files (may contain sensitive data)
- `conf/state.yml` - Backend configuration with sensitive values
- `.venv/`, `venv/`, `node_modules/` - Dependency directories
- `__pycache__/` - Python bytecode cache
