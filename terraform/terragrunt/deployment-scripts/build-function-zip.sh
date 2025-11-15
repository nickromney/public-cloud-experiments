#!/bin/bash
# Build optimized deployment package for Azure Function App
# Excludes test files, development tools, and unnecessary artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FUNCTION_APP_DIR="$REPO_ROOT/subnet-calculator/api-fastapi-azure-function"
OUTPUT_ZIP="${1:-$SCRIPT_DIR/function-app.zip}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building optimized deployment package for Azure Function App"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Copying Function App files..."
cd "$FUNCTION_APP_DIR"

# Verify all required files exist before copying
REQUIRED_FILES=("auth.py" "config.py" "function_app.py" "host.json" "requirements.txt")
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Error: Required file not found: $file"
    exit 1
  fi
done

# Copy entire function app (excluding dev artifacts) so Azure can register functions
rsync -a \
  --exclude '.git/' \
  --exclude '.github/' \
  --exclude '.venv/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  --exclude '.ruff_cache/' \
  --exclude 'tests/' \
  --exclude 'test*/' \
  --exclude 'test*.py' \
  --exclude 'bruno-collections/' \
  --exclude 'Dockerfile' \
  --exclude 'compose.yml' \
  --exclude 'CLAUDE.md' \
  --exclude 'README.md' \
  --exclude 'uv.lock' \
  --exclude 'pyproject.toml' \
  --exclude 'local.settings.json' \
  "$FUNCTION_APP_DIR/" "$TEMP_DIR/"

cd "$TEMP_DIR"

# Note: Skipping local dependency installation since Azure Functions
# will build remotely with --build-remote true using the correct Python version
echo "Skipping local dependency installation (Azure will build remotely)..."

echo "Files included in deployment:"
find . -type f | sort

# Create zip
echo ""
echo "Creating optimized zip: $OUTPUT_ZIP"
rm -f "$OUTPUT_ZIP"
zip -r "$OUTPUT_ZIP" . \
  -x "*.git*" \
  -x "*.DS_Store" \
  -x "__pycache__/*" \
  -x "*.pyc" \
  -x "*.pyo" \
  -x "*.pyd"

echo ""
echo "✅ Optimized deployment package created: $OUTPUT_ZIP"
echo "   Size: $(du -h "$OUTPUT_ZIP" | cut -f1)"
echo "   Files included:"
echo "     - auth.py (JWT authentication)"
echo "     - config.py (configuration management)"
echo "     - function_app.py (main application)"
echo "     - host.json (Azure Functions host config)"
echo "     - requirements.txt (Python dependencies)"
echo ""
echo "   Files excluded (not needed in production):"
echo "     - test_*.py (108 test files)"
echo "     - test_*.sh (shell test scripts)"
echo "     - bruno-collections/ (API testing)"
echo "     - .venv/ (local virtual environment)"
echo "     - __pycache__/ (Python cache)"
echo "     - .pytest_cache/ (pytest cache)"
echo "     - .ruff_cache/ (linter cache)"
echo "     - uv.lock (local dependency lock)"
echo "     - CLAUDE.md, README.md (documentation)"
echo "     - Dockerfile, compose.yml (container configs)"
echo "     - pyproject.toml (local dev config)"
echo "     - local.settings.json (local dev settings)"
echo ""
echo "💡 Deploy with:"
echo "   az functionapp deployment source config-zip \\"
echo "     --resource-group <rg-name> \\"
echo "     --name <function-app-name> \\"
echo "     --src $OUTPUT_ZIP"
