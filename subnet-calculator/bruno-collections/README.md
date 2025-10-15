# Bruno API Test Collections

This directory contains Bruno API test collections for the Subnet Calculator stacks.

## Structure

```text
bruno-collections/
├── bruno.json                         # Collection configuration
├── environments/
│   └── local.bru                     # Local environment variables
├── Stack 4 - No Auth/
│   ├── Health Check.bru              # Test health endpoint
│   ├── Validate IP.bru               # Test IP validation
│   └── Subnet Info.bru               # Test subnet calculation
├── Stack 5 - JWT Auth/
│   ├── Login.bru                     # Get JWT token (saves to env)
│   ├── Health Check.bru              # Test authenticated health check
│   └── Subnet Info.bru               # Test authenticated subnet calculation
└── Stack 6 - Entra ID Auth/
    ├── Check Auth Status.bru         # Check SWA authentication status
    ├── Health Check.bru              # Test with cookie-based auth
    └── Subnet Info.bru               # Test authenticated subnet calculation
```

## Prerequisites

```bash
# No installation needed - Makefile uses npx
# Or install globally:
npm install -g @usebruno/cli
```

## Environments

This collection includes two environments:

- **local** - For local development with SWA CLI (ports 4280-4282)
- **production** - For testing deployed Azure Static Web Apps

To use production environment:

1. Edit `environments/production.bru`
2. Update URLs to your deployed app URLs
3. Select "production" in Bruno GUI dropdown (top-right)

## Running Tests

### Via Makefile (Recommended)

```bash
# Terminal 1: Start the stack you want to test
make start-stack4
# or
make start-stack5

# Terminal 2: Run the matching test
make test-bruno-stack4
# or
make test-bruno-stack5
```

**Important**: Only ONE stack can run at a time due to port conflicts (3000, 7071). Always run the test matching your running stack.

### Via Bruno CLI Directly

```bash
# Run all collections (must be inside bruno-collections directory)
cd bruno-collections
npx @usebruno/cli@latest run --env local -r

# Run specific collection
npx @usebruno/cli@latest run "Stack 4 - No Auth" --env local

# Output to JSON
npx @usebruno/cli@latest run --env local --output results.json --format json -r

# Back to project root
cd ..
```

### Via Bruno GUI

```bash
# Install Bruno desktop application
brew install --cask bruno

# Open Bruno and load the collection
# File > Open Collection > Select bruno-collections directory
```

## Environment Variables

The `environments/local.bru` file defines:

- `stack4BaseUrl`: <http://localhost:4280> (Stack 4 - No Auth)
- `stack5BaseUrl`: <http://localhost:4281> (Stack 5 - JWT Auth)
- `stack6BaseUrl`: <http://localhost:4282> (Stack 6 - Entra ID Auth)
- `token`: Automatically populated by Stack 5 Login request

## How It Works

### Stack 4 (No Auth)

All requests are sent directly without authentication:

1. Health Check - Verify API is healthy
2. List Providers - Get available cloud providers
3. Calculate Subnet - Calculate Azure subnet (10.0.0.0/24)

### Stack 5 (JWT Auth)

Requests require JWT token in Authorization header:

1. Login - POST credentials, get token (saved to environment)
2. Health Check - GET with `Authorization: Bearer {{token}}`
3. Calculate Subnet - POST with authentication

The Login request automatically saves the token to the environment variable, so subsequent requests can use `{{token}}`.

### Stack 6 (Entra ID Auth)

Authentication via SWA platform (cookie-based):

1. Check Auth Status - GET /.auth/me (SWA endpoint)
2. Health Check - GET with cookie authentication
3. Subnet Info - POST with cookie authentication

**Important:** Stack 6 uses browser-based login. The CLI tests check unauthenticated access. For authenticated tests, use Bruno GUI and login via browser first:

```bash
# Open browser and login
open http://localhost:4282/.auth/login/aad
# Login with any email (SWA CLI emulation)

# Then run Bruno GUI tests with cookies
```

## Expected Results

All tests include assertions and will fail if:

- HTTP status is not 200
- Response body doesn't match expected structure
- Required fields are missing

## Troubleshooting

### Error: "ECONNREFUSED"

- Make sure the stack is running (`make start-stack4` or `make start-stack5`)

### Error: "401 Unauthorized" on Stack 5

- Run the Login request first to get a fresh token
- Token expires after 1 hour

### Error: "Collection not found"

- Run from the `subnet-calculator` directory
- Check that `bruno-collections/` exists

## Testing Production Deployments

### Stack 4 (No Auth) - CLI and GUI

**Bruno CLI:**

```bash
cd bruno-collections
npx @usebruno/cli@latest run "Stack 4 - No Auth" --env production
```

Works perfectly - no authentication required.

### Stack 5 (JWT Auth) - CLI and GUI

**Bruno CLI:**

```bash
cd bruno-collections
npx @usebruno/cli@latest run "Stack 5 - JWT Auth" --env production
```

Works perfectly - login endpoint is part of your API.

### Stack 6 (Entra ID Auth) - GUI Only

**Bruno CLI:** DOES NOT WORK for authenticated tests (OAuth flow requires browser)

**Bruno GUI with Manual Login:**

1. Open browser and login to your deployed app:

   ```bash
   open https://your-stack6-app.azurestaticapps.net/.auth/login/aad
   ```

2. Complete Entra ID login in browser

3. Open Bruno GUI and run tests:
   - Bruno GUI shares browser cookies
   - Authenticated requests will work
   - Environment: Select "production"

**Limitation:** Bruno CLI cannot handle browser-based OAuth flows. Stack 6 production testing requires Bruno GUI after manual browser login.

### Summary Matrix

| Stack | Bruno CLI | Bruno GUI | Notes |
|-------|-----------|-----------|-------|
| Stack 4 (No Auth) | YES | YES | Just change environment |
| Stack 5 (JWT) | YES | YES | Login via API endpoint |
| Stack 6 (Entra ID) | NO* | YES** | *Unauthenticated only, **After browser login |

## Security Inspection

To understand what an interested security researcher would see when inspecting traffic for each stack, see:

**[SECURITY-INSPECTION.md](../SECURITY-INSPECTION.md)**

This guide explains:

- What headers/cookies are visible in each stack
- How to decode JWT tokens (Stack 5)
- Cookie-based auth security (Stack 6)
- What a researcher can and cannot do
- Comparison of security models

**Using Bruno GUI for inspection:**

1. Open Bruno and load this collection
2. Select "local" environment (top-right)
3. Run requests
4. Inspect the **Headers** and **Cookies** tabs
5. Compare the different authentication mechanisms

## Adding More Tests

To add a new test:

1. Create a `.bru` file in the appropriate stack directory
2. Set the `seq` number for execution order
3. Use `{{stack4BaseUrl}}` or `{{stack5BaseUrl}}` for the URL
4. Add assertions and tests
5. For Stack 5, use `auth: bearer` with `token: {{token}}`

Example:

```bruno
meta {
  name: My Test
  type: http
  seq: 4
}

get {
  url: {{stack4BaseUrl}}/api/v1/endpoint
  body: none
  auth: none
}

assert {
  res.status: eq 200
}

tests {
  test("should do something", function() {
    expect(res.getStatus()).to.equal(200);
  });
}
```
