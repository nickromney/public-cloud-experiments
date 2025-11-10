#!/usr/bin/env bash
#
# Mock build-deployment-zip.sh for testing
# Tracks calls and creates dummy zip file

# Track call to file
BUILD_SCRIPT_CALLS_FILE="${BUILD_SCRIPT_CALLS_FILE:-/tmp/build_script_calls_$$}"
echo "build-deployment-zip.sh $*" >> "$BUILD_SCRIPT_CALLS_FILE"

# Check if mock should fail
if [[ "${MOCK_BUILD_FAIL:-false}" == "true" ]]; then
  echo "ERROR: Build script failed (mocked)" >&2
  exit 1
fi

# Get output path
OUTPUT_ZIP="$1"

if [ -z "$OUTPUT_ZIP" ]; then
  echo "ERROR: Output zip path required" >&2
  exit 1
fi

# Create dummy zip file
echo "Building React deployment package..."
echo "API_BASE_URL=${API_BASE_URL:-https://mock-api.example.com}"
echo "mock-react-app-content" > /tmp/mock-react.txt
zip -q "$OUTPUT_ZIP" /tmp/mock-react.txt 2>/dev/null || touch "$OUTPUT_ZIP"
echo "React package built: $OUTPUT_ZIP"

exit 0
