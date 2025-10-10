#!/usr/bin/env bash
#
# Check prerequisites for Azure subnet calculator deployment
# - Azure CLI
# - Azure Functions Core Tools
# - Static Web Apps CLI
# - Node.js and npm
# - Python and uv
#
# Usage: ./prerequisites.sh

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

echo "Checking prerequisites for Azure deployment..."
echo ""

MISSING_TOOLS=()
WARNINGS=()

# Check Azure CLI
if command -v az &>/dev/null; then
  AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  log_info "Azure CLI: $AZ_VERSION"

  # Check if logged in
  if az account show --only-show-errors &>/dev/null 2>&1; then
    SUBSCRIPTION=$(az account show --query name -o tsv)
    log_info "Azure: logged in ($SUBSCRIPTION)"
  else
    log_warn "Azure CLI: not logged in (run 'az login')"
    WARNINGS+=("Azure: Not logged in")
  fi
else
  log_error "Azure CLI: not installed"
  MISSING_TOOLS+=("azure-cli")
  echo "  Install: brew install azure-cli"
fi

echo ""

# Check Azure Functions Core Tools
if command -v func &>/dev/null; then
  FUNC_VERSION=$(func --version 2>/dev/null || echo "unknown")
  log_info "Azure Functions Core Tools: $FUNC_VERSION"
else
  log_error "Azure Functions Core Tools: not installed"
  MISSING_TOOLS+=("azure-functions-core-tools")
  echo "  Install: brew install azure-functions-core-tools"
fi

echo ""

# Check Node.js and npm
if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version)
  NPM_VERSION=$(npm --version)
  log_info "Node.js: $NODE_VERSION"
  log_info "npm: $NPM_VERSION"
else
  log_error "Node.js: not installed"
  MISSING_TOOLS+=("node")
  echo "  Install: brew install node"
fi

echo ""

# Check Static Web Apps CLI
if command -v swa &>/dev/null; then
  SWA_VERSION=$(swa --version 2>/dev/null | head -1 || echo "unknown")
  log_info "Static Web Apps CLI: $SWA_VERSION"
else
  log_warn "Static Web Apps CLI: not installed (will auto-install during deployment)"
  WARNINGS+=("Static Web Apps CLI: Will be installed automatically")
  echo "  Optional install: npm install -g @azure/static-web-apps-cli"
fi

echo ""

# Check Python and uv
if command -v python3 &>/dev/null; then
  PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
  log_info "Python: $PYTHON_VERSION"
else
  log_error "Python 3: not installed"
  MISSING_TOOLS+=("python3")
  echo "  Install: brew install python@3.11"
fi

if command -v uv &>/dev/null; then
  UV_VERSION=$(uv --version | cut -d' ' -f2)
  log_info "uv: $UV_VERSION"
else
  log_error "uv: not installed"
  MISSING_TOOLS+=("uv")
  echo "  Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

echo ""
echo "================================================================"

# Summary
if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
  log_info "All required tools are installed!"

  if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    log_warn "Warnings:"
    for warning in "${WARNINGS[@]}"; do
      echo "  - $warning"
    done
  fi

  echo ""
  log_info "You're ready to deploy!"
  echo ""
  echo "Next steps:"
  echo "  1. ./setup-env.sh          # Configure environment"
  echo "  2. make create-all         # Create infrastructure"
  echo "  3. make deploy-all         # Deploy applications"
  exit 0
else
  log_error "Missing required tools:"
  for tool in "${MISSING_TOOLS[@]}"; do
    echo "  - $tool"
  done
  echo ""
  log_error "Please install missing tools before proceeding"
  echo ""
  echo "Quick install (macOS):"
  echo "  brew install azure-cli azure-functions-core-tools node"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi
