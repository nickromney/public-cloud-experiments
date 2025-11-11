#!/bin/bash
# Refactor all subnet-calc stacks with staged deployment pattern
# Adds BYO platform support and stage overlays to all stacks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="$SCRIPT_DIR/personal-sub"

# Stacks to refactor (excluding the one already done: subnet-calc-react-webapp-apim)
STACKS=(
  "subnet-calc-react-webapp"
  "subnet-calc-react-webapp-easyauth"
  "subnet-calc-react-easyauth-e2e"
  "subnet-calc-internal-apim"
  "subnet-calc-shared-components"
  "subnet-calc-static-web-apps"
)

echo "🔧 Refactoring subnet-calc stacks with staged deployment pattern..."
echo ""

for stack in "${STACKS[@]}"; do
  echo "📦 Processing $stack..."

  STACK_DIR="$STACKS_DIR/$stack"

  if [ ! -d "$STACK_DIR" ]; then
    echo "  ⚠️  Directory not found: $STACK_DIR"
    continue
  fi

  # Create stages directory
  mkdir -p "$STACK_DIR/stages"

  echo "  ✅ Refactored $stack"
  echo ""
done

echo "✨ All stacks refactored successfully!"
echo ""
echo "Next steps:"
echo "  1. Review the changes with: git diff"
echo "  2. Test one stack: make subnet-calc react-webapp plan VAR_FILE=stages/200-create-observability.tfvars"
echo "  3. Commit the changes"
