#!/bin/bash
# Build deployment package for React Web App with shared-frontend dependency
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
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
VITE_API_BASE_URL="${API_BASE_URL:-https://func-subnet-calc-react-api.azurewebsites.net}" \
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

# Fix paths - shared-frontend is now a subdirectory instead of sibling
cd "$TEMP_DIR"

# Fix package.json file: dependency path
sed -i.bak 's|"file:../shared-frontend"|"file:./shared-frontend"|g' package.json
rm -f package.json.bak

# Fix package-lock.json as well
sed -i.bak 's|"file:../shared-frontend"|"file:./shared-frontend"|g' package-lock.json
rm -f package-lock.json.bak

# Fix tsconfig paths
sed -i.bak 's|"../shared-frontend/tsconfig.json"|"./shared-frontend/tsconfig.json"|g' tsconfig.app.json
sed -i.bak 's|"../shared-frontend/|"./shared-frontend/|g' tsconfig.app.json
sed -i.bak 's|{ "path": "../shared-frontend" }|{ "path": "./shared-frontend" }|g' tsconfig.app.json
rm -f tsconfig.app.json.bak

# Fix CSS import paths in source files (../../shared-frontend -> ../shared-frontend)
# Handle both single and double quotes
find src -type f \( -name "*.tsx" -o -name "*.ts" \) -exec sed -i.bak "s|'../../shared-frontend/|'../shared-frontend/|g; s|\"../../shared-frontend/|\"../shared-frontend/|g" {} \;
find src -type f -name "*.bak" -delete

# Fix vite.config.ts alias paths
sed -i.bak "s|'../shared-frontend/|'./shared-frontend/|g" vite.config.ts
rm -f vite.config.ts.bak

# Clean up unnecessary files
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
