#!/bin/bash
# test_endpoints.sh - API endpoint testing script
# Tests all endpoints using xh (preferred) or curl (fallback)

# Show help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [URL]

Test the subnet calculator API endpoints.

OPTIONS:
    --detailed      Run all endpoints with full command output
    --container     Test containerized API (http://localhost:8080/api)
    --help, -h      Show this help message

EXAMPLES:
    $0                      # Smoke test on local API (port 7071)
    $0 --detailed           # All endpoints on local API (port 7071)
    $0 --container          # Smoke test on containerized API (port 8080)
    $0 --detailed --container  # All endpoints on container
    $0 --detailed https://your-api.azurewebsites.net/api   # All endpoints on Azure

REQUIREMENTS:
    - API must be running before executing tests
    - Either 'xh' or 'curl' must be installed

Start the local API with:
    func start              # For local Azure Functions (port 7071)
    podman run ...          # For containerized API (port 8080)

EOF
}

# Parse arguments
DETAILED=false
BASE_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        --container)
            BASE_URL="http://localhost:8080/api"
            shift
            ;;
        *)
            BASE_URL="$1"
            shift
            ;;
    esac
done

# Set default if not specified
if [ -z "$BASE_URL" ]; then
    BASE_URL="http://localhost:7071/api"
fi

# Detect which HTTP client to use
if command -v xh &> /dev/null; then
    HTTP_CLIENT="xh"
    echo "Using xh for HTTP requests"
elif command -v curl &> /dev/null; then
    HTTP_CLIENT="curl"
    echo "Using curl for HTTP requests"
else
    echo "Error: Neither xh nor curl found. Please install one of them."
    exit 1
fi

# Helper function for POST requests
post_json() {
    local endpoint=$1
    shift

    if [ "$HTTP_CLIENT" = "xh" ]; then
        local cmd="xh POST $BASE_URL/$endpoint $*"
        if [ "$DETAILED" = true ]; then
            echo "$ $cmd"
        fi
        xh POST "$BASE_URL/$endpoint" "$@"
    else
        # Build JSON from key=value pairs
        local json="{"
        local first=true
        for arg in "$@"; do
            if [ "$first" = true ]; then
                first=false
            else
                json="${json},"
            fi
            local key="${arg%%=*}"
            local value="${arg#*=}"
            json="${json}\"${key}\":\"${value}\""
        done
        json="${json}}"

        if [ "$DETAILED" = true ]; then
            echo "$ curl -X POST $BASE_URL/$endpoint \\"
            echo "    -H \"Content-Type: application/json\" \\"
            echo "    -d '$json'"
        fi

        curl -X POST "$BASE_URL/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$json"
        echo  # Add newline after curl output
    fi
}

# Helper function for GET requests
get_request() {
    local endpoint=$1

    if [ "$HTTP_CLIENT" = "xh" ]; then
        local cmd="xh GET $BASE_URL/$endpoint"
        if [ "$DETAILED" = true ]; then
            echo "$ $cmd"
        fi
        xh GET "$BASE_URL/$endpoint"
    else
        if [ "$DETAILED" = true ]; then
            echo "$ curl $BASE_URL/$endpoint"
        fi
        curl "$BASE_URL/$endpoint"
        echo  # Add newline after curl output
    fi
}

echo ""
echo "========================================="
if [ "$DETAILED" = true ]; then
    echo "Detailed API Test: $BASE_URL"
else
    echo "Smoke Test: $BASE_URL"
fi
echo "========================================="

# Test connectivity first
echo ""
echo "Checking API connectivity..."
if ! get_request "v1/health" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: Cannot connect to API at $BASE_URL"
    echo ""
    echo "Make sure the API is running:"
    if [[ "$BASE_URL" == *"7071"* ]]; then
        echo "  func start"
    elif [[ "$BASE_URL" == *"8080"* ]]; then
        echo "  podman run --platform linux/amd64 --rm -it --init -p 8080:80 subnet-calculator-python-api:v1"
    else
        echo "  Check that your Azure deployment is accessible"
    fi
    echo ""
    show_help
    exit 1
fi

echo "✓ API is reachable"
echo ""

if [ "$DETAILED" = false ]; then
    # SMOKE TEST - Quick validation of key endpoints
    echo "Running smoke test (use --detailed for all endpoints)..."
    echo ""

    echo "1. Health Check"
    echo "---"
    get_request "v1/health"

    echo ""
    echo "2. Validate IPv4 Address"
    echo "---"
    post_json "v1/ipv4/validate" "address=192.168.1.1"

    echo ""
    echo "3. Check RFC1918 Private Address"
    echo "---"
    post_json "v1/ipv4/check-private" "address=192.168.1.1"

    echo ""
    echo "4. Check Cloudflare Range"
    echo "---"
    post_json "v1/ipv4/check-cloudflare" "address=104.16.1.1"

    echo ""
    echo "5. Subnet Info (Azure Mode)"
    echo "---"
    post_json "v1/ipv4/subnet-info" "network=192.168.1.0/24" "mode=Azure"

    echo ""
    echo "========================================="
    echo "✓ Smoke test passed!"
    echo "Run with --detailed to test all endpoints"
    echo "========================================="
    exit 0
fi

# DETAILED TEST - All endpoints
echo "Running detailed test of all endpoints..."
echo ""

echo "1. Health Check"
echo "---"
get_request "v1/health"

echo ""
echo "2. Validate IPv4 Address"
echo "---"
post_json "v1/ipv4/validate" "address=192.168.1.1"

echo ""
echo "3. Validate IPv4 Network (CIDR)"
echo "---"
post_json "v1/ipv4/validate" "address=192.168.1.0/24"

echo ""
echo "4. Validate IPv6 Address"
echo "---"
post_json "v1/ipv4/validate" "address=2606:4700::1"

echo ""
echo "5. Check RFC1918 Private Address (192.168.x)"
echo "---"
post_json "v1/ipv4/check-private" "address=192.168.1.1"

echo ""
echo "6. Check RFC1918 Private Address (10.x)"
echo "---"
post_json "v1/ipv4/check-private" "address=10.0.0.1"

echo ""
echo "7. Check RFC6598 Shared Address Space"
echo "---"
post_json "v1/ipv4/check-private" "address=100.64.1.1"

echo ""
echo "8. Check Public Address (not RFC1918/RFC6598)"
echo "---"
post_json "v1/ipv4/check-private" "address=8.8.8.8"

echo ""
echo "9. Check Cloudflare IPv4 Range"
echo "---"
post_json "v1/ipv4/check-cloudflare" "address=104.16.1.1"

echo ""
echo "10. Check Cloudflare IPv6 Range"
echo "---"
post_json "v1/ipv4/check-cloudflare" "address=2606:4700::1"

echo ""
echo "11. Check Non-Cloudflare Address"
echo "---"
post_json "v1/ipv4/check-cloudflare" "address=8.8.8.8"

echo ""
echo "12. Subnet Info - Azure Mode (default)"
echo "---"
post_json "v1/ipv4/subnet-info" "network=192.168.1.0/24"

echo ""
echo "13. Subnet Info - AWS Mode"
echo "---"
post_json "v1/ipv4/subnet-info" "network=10.0.0.0/24" "mode=AWS"

echo ""
echo "14. Subnet Info - OCI Mode"
echo "---"
post_json "v1/ipv4/subnet-info" "network=10.0.0.0/24" "mode=OCI"

echo ""
echo "15. Subnet Info - Standard Mode"
echo "---"
post_json "v1/ipv4/subnet-info" "network=10.0.0.0/24" "mode=Standard"

echo ""
echo "16. Subnet Info - /31 Point-to-Point"
echo "---"
post_json "v1/ipv4/subnet-info" "network=10.0.0.0/31"

echo ""
echo "17. Subnet Info - /32 Single Host"
echo "---"
post_json "v1/ipv4/subnet-info" "network=10.0.0.5/32"

echo ""
echo "========================================="
echo "All tests completed!"
echo "========================================="
