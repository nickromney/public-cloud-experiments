# Subnet Calculator - React Frontend

React + TypeScript + Vite frontend for the subnet calculator with flexible authentication.

## Features

- **React 18** with TypeScript and Vite for fast development
- **Hybrid Authentication** - Auto-detects deployment environment:
  - Azure Web App: Easy Auth (platform-level)
  - Azure Container Apps: Easy Auth (platform-level)
  - Azure Static Web Apps: Entra ID via SWA
  - Local Development: MSAL (application-level OAuth)
  - Optional: No authentication
- **Dual-stack IP Support** - Both IPv4 and IPv6
- **Performance Timing** - Detailed API call timing with collapsible details
- **Responsive Design** - Mobile-first, works on all screen sizes
- **Dark/Light Theme** - User preference with persistence

## Architecture

### Authentication Flow

The frontend detects the deployment environment and uses the appropriate auth method:

```typescript
// config.ts determines auth method:
1. Check RUNTIME_CONFIG (injected by deployment)
2. Check VITE_AUTH_METHOD environment variable
3. Auto-detect from hostname:
   - *.azurewebsites.net → Easy Auth
   - *.azurecontainerapps.io → Easy Auth
   - *.azurestaticapps.net → Entra ID (SWA)
4. Check for MSAL config → MSAL
5. Default → No authentication
```

### Directory Structure

```text
src/
├── api/
│   └── client.ts          # API client with IPv4/IPv6 support
├── auth/
│   ├── AuthContext.tsx    # Unified auth context
│   ├── easyAuthProvider.ts # Easy Auth implementation
│   └── msalConfig.ts      # MSAL configuration
├── components/            # React components (TODO)
├── config.ts             # Runtime configuration
└── types.ts              # TypeScript type definitions
```

## Development

### Prerequisites

```bash
npm install
```

### Run Locally

```bash
# No authentication
npm run dev

# With MSAL (requires App Registration)
VITE_AUTH_METHOD=msal \
VITE_AZURE_CLIENT_ID="your-client-id" \
VITE_AZURE_TENANT_ID="your-tenant-id" \
npm run dev
```

### Configuration

#### Environment Variables

- `VITE_API_URL`: Backend API URL (default: `http://localhost:7071`)
- `VITE_AUTH_METHOD`: `none` | `easyauth` | `msal` | `entraid-swa`
- `VITE_AZURE_CLIENT_ID`: Azure AD app client ID (MSAL only)
- `VITE_AZURE_TENANT_ID`: Azure AD tenant ID (MSAL only)
- `VITE_AZURE_REDIRECT_URI`: OAuth redirect URI (MSAL only)

#### Runtime Configuration

For scenarios where build-time config isn't suitable, inject runtime config:

```html
<script>
  window.RUNTIME_CONFIG = {
    API_BASE_URL: 'https://api.example.com',
    AUTH_METHOD: 'easyauth',
  };
</script>
<script type="module" src="/src/main.tsx"></script>
```

## Deployment

### Azure Web App with Easy Auth

1. Deploy React app to Azure Web App
2. Enable Easy Auth in Azure Portal (App Service Authentication)
3. Configure Entra ID provider
4. No code changes needed - auto-detects Easy Auth from hostname

### Azure Container Apps with Easy Auth

1. Deploy React app to Azure Container Apps
2. Enable Easy Auth via `az containerapp auth update`
3. No code changes needed - auto-detects Easy Auth from hostname

### Azure Static Web Apps with Entra ID

1. Deploy via `swa deploy` or GitHub Actions
2. Configure authentication in `staticwebapp.config.json`
3. No code changes needed - auto-detects SWA from hostname

### AKS with OAuth2 Proxy Sidecar

1. Deploy OAuth2 Proxy as sidecar container
2. Configure OAuth2 Proxy to inject headers
3. Set `VITE_AUTH_METHOD=easyauth` (OAuth2 Proxy mimics Easy Auth)

## Testing

```bash
# Unit tests
npm test

# E2E tests with Playwright
npm run test:e2e

# Type checking
npm run type-check

# Linting
npm run lint
```

## Docker Build

```bash
docker build -t subnet-calculator-react .
docker run -p 8080:80 subnet-calculator-react
```

## Status

**Work In Progress** - Initial architecture and authentication completed.

### Completed

- [x] Project structure with Vite + React + TypeScript
- [x] Flexible configuration system
- [x] Hybrid authentication (Easy Auth + MSAL + SWA + None)
- [x] API client with IPv4/IPv6 support
- [x] Performance timing infrastructure

### TODO

- [ ] React UI components
- [ ] Results display
- [ ] Theme switching
- [ ] Docker configuration
- [ ] Tests
- [ ] Complete documentation
