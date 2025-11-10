#!/usr/bin/env bash
#
# Mock build-function-zip.sh for testing
# Tracks calls and creates dummy zip file

# Track call to file
BUILD_SCRIPT_CALLS_FILE="${BUILD_SCRIPT_CALLS_FILE:-/tmp/build_script_calls_$$}"
echo "build-function-zip.sh $*" >> "$BUILD_SCRIPT_CALLS_FILE"

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
echo "Building Function App deployment package..."
echo "mock-function-app-content" > /tmp/mock-function.txt
zip -q "$OUTPUT_ZIP" /tmp/mock-function.txt 2>/dev/null || touch "$OUTPUT_ZIP"
echo "Function App package built: $OUTPUT_ZIP"

exit 0
