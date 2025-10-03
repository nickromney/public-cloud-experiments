# public-cloud-experiments

Investigations into various cloud technologies, typically on Azure, with some AWS

## Projects

### Subnet Calculator

A full-stack IPv4/IPv6 subnet calculator with REST API backend and web frontend.

**Quick Start:**

```bash
cd subnet-calculator
docker compose up
```

Access at `http://localhost:8000` (frontend) and `http://localhost:8080/api/v1/docs` (API docs).

**Features:**

- IPv4/IPv6 address validation and CIDR notation support
- RFC1918/RFC6598 private address detection
- Cloudflare IP range detection
- Cloud provider-specific subnet calculations (Azure, AWS, OCI, Standard)
- Modern responsive web UI with dark/light mode
- Interactive Swagger UI API documentation

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
│   ├── docker-compose.yml            # Docker Compose configuration
│   ├── compose.yml                   # Podman Compose configuration
│   ├── README.md                     # Project documentation
│   ├── api-fastapi-azure-function/   # Backend API (FastAPI + Azure Functions)
│   │   ├── function_app.py           # FastAPI app with validation
│   │   ├── test_function_app.py      # pytest test suite
│   │   ├── Dockerfile                # Azure Functions Python 3.11 runtime
│   │   ├── host.json                 # Azure Functions configuration
│   │   └── README.md
│   └── frontend-python-flask/        # Frontend (Flask + Pico CSS)
│       ├── app.py                    # Flask application
│       ├── templates/                # Jinja2 templates
│       ├── static/                   # CSS/JS assets
│       ├── Dockerfile
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

```bash
cd subnet-calculator
docker compose up
```

Access the frontend at `http://localhost:8000` and API documentation at `http://localhost:8080/api/v1/docs`.

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
