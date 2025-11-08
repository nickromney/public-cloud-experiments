#!/bin/bash
# Build deployment package for React Web App with shared-frontend dependency
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
FRONTEND_REACT_DIR="$REPO_ROOT/subnet-calculator/frontend-react"
SHARED_FRONTEND_DIR="$REPO_ROOT/subnet-calculator/shared-frontend"
OUTPUT_ZIP="${1:-$SCRIPT_DIR/react-app.zip}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building deployment package for React Web App"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Build shared-frontend
echo "Building shared-frontend..."
cd "$SHARED_FRONTEND_DIR"
npm install
npm run build

# Build frontend-react
echo "Building frontend-react..."
cd "$FRONTEND_REACT_DIR"
npm install
VITE_API_BASE_URL="${API_BASE_URL:-https://func-subnet-calc-react-api.azurewebsites.net/api/v1}" \
VITE_AUTH_METHOD=jwt \
VITE_JWT_USERNAME=demo \
VITE_JWT_PASSWORD=password123 \
npm run build

# Create deployment structure
echo "Creating deployment structure..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Copy frontend-react files
cp -r "$FRONTEND_REACT_DIR"/* "$TEMP_DIR/"

# Copy shared-frontend (needed for file: dependency)
mkdir -p "$TEMP_DIR/shared-frontend"
cp -r "$SHARED_FRONTEND_DIR"/* "$TEMP_DIR/shared-frontend/"

# Clean up unnecessary files
cd "$TEMP_DIR"
rm -rf node_modules .git test-results playwright-report .ruff_cache __pycache__
rm -rf shared-frontend/node_modules shared-frontend/.git shared-frontend/coverage

# Create zip from the deployment directory
echo "Creating zip: $OUTPUT_ZIP"
rm -f "$OUTPUT_ZIP"
zip -r "$OUTPUT_ZIP" . \
  -x "*.git*" \
  -x "*node_modules/*" \
  -x "*test-results/*" \
  -x "*playwright-report/*" \
  -x "*.DS_Store"

echo "✅ Deployment package created: $OUTPUT_ZIP"
echo "   Size: $(du -h "$OUTPUT_ZIP" | cut -f1)"
