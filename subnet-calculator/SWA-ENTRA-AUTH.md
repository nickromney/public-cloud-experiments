# Stack 6: Azure Static Web Apps with Entra ID Authentication

Stack 6 demonstrates Azure Static Web Apps **platform-level authentication** using Microsoft Entra ID (formerly Azure AD).

## Architecture

### Authentication Layer: SWA Platform

- SWA CLI handles all authentication
- No custom auth code in frontend or backend
- Emulated locally, real Entra ID in production

### Frontend: TypeScript + Vite

- Same as Stack 4 (no custom auth code)
- Access user info via `/.auth/me`
- Login/logout via `/.auth/login/aad` and `/.auth/logout`

### Backend: Azure Function

- `AUTH_METHOD=none` (same as Stack 4)
- No JWT validation needed
- SWA passes authenticated user via headers

## Key Differences from Stack 5

| Feature | Stack 5 (JWT) | Stack 6 (Entra ID) |
|---------|---------------|-------------------|
| Auth Layer | Application | Platform (SWA) |
| Login Endpoint | `/api/v1/auth/login` | `/.auth/login/aad` |
| Backend Auth | Custom JWT validation | None (SWA handles it) |
| User Management | Custom (test users) | Entra ID directory |
| Deployment | Complex | Simple (just config) |

## How It Works

### 1. User Access

```text
User → /.auth/login/aad → Entra ID → SWA validates → Your App
```

### 2. Protected Routes (staticwebapp.config.json)

```json
{
 "routes": [
 {
 "route": "/api/*",
 "allowedRoles": ["authenticated"]
 }
 ]
}
```

### 3. User Info Available

```javascript
// Frontend can call:
const response = await fetch('/.auth/me')
const user = await response.json()
// Returns: { clientPrincipal: { userId, userRoles, claims } }
```

### 4. Backend Receives Headers

```text
x-ms-client-principal: base64-encoded user info
x-ms-client-principal-id: user ID
x-ms-client-principal-name: user name
```

## Local Development with SWA CLI

The SWA CLI **emulates** Entra ID authentication for local testing:

```bash
make start-stack6
# Opens: http://localhost:4282
```

### Emulated Auth Flow

1. Click "Login with Azure AD" (emulated button)
2. SWA CLI shows a fake login screen
3. Enter any email/username (no password needed locally)
4. SWA CLI sets authentication cookies
5. Your app receives the authenticated user

**IMPORTANT LIMITATIONS - Local Development:**

The SWA CLI emulator does NOT fully enforce route protection:

- `staticwebapp.config.json` routes with `allowedRoles` are NOT enforced locally
- You can access <http://localhost:4282> without logging in (even though config requires auth)
- API endpoints MAY enforce auth (backend-level checking)
- This is a **known limitation** of the SWA CLI emulator

**In Production (Azure):**

- Route protection IS enforced
- Accessing <http://your-app.azurestaticapps.net> WILL redirect to login
- All routes respect `allowedRoles` configuration

**Testing Recommendation:**

- Use local development to test functionality
- Deploy to Azure preview environment to test full authentication flow
- See: <https://github.com/Azure/static-web-apps-cli/issues/630>

## Production Setup

### 1. Register App in Entra ID

```bash
# Azure Portal > App Registrations > New Registration
# Set Redirect URI: https://your-app.azurestaticapps.net/.auth/login/aad/callback
```

### 2. Configure Static Web App

```bash
az staticwebapp appsettings set \
 --name your-swa \
 --setting-names \
 AZURE_CLIENT_ID=your-client-id \
 AZURE_CLIENT_SECRET=your-client-secret
```

### 3. Deploy

```bash
# Static Web App reads staticwebapp.config.json automatically
swa deploy
```

## Testing Stack 6

### Start the Stack

```bash
cd ~/Developer/personal/public-cloud-experiments/subnet-calculator
make start-stack6
```

### Access Points

- **App**: <http://localhost:4282>
- **Login**: <http://localhost:4282/.auth/login/aad>
- **User Info**: <http://localhost:4282/.auth/me>
- **Logout**: <http://localhost:4282/.auth/logout>

### Test Flow

1. Go to <http://localhost:4282>
2. Try to call API → SWA redirects to login
3. Login with any email (SWA CLI emulation)
4. API calls now work with authenticated user

## Advantages of SWA Platform Auth

 **Zero auth code** - SWA handles everything
 **Enterprise SSO** - Entra ID integration
 **Role-based access** - Configure in staticwebapp.config.json
 **Multiple providers** - GitHub, Twitter, custom OIDC
 **Audit logs** - Built into Azure
 **Token refresh** - Automatic
 **Security patches** - Microsoft maintains

## When to Use Stack 6 vs Stack 5

**Use Stack 6 (Entra ID) when:**

- Enterprise customers (Azure AD/Entra ID)
- Need SSO integration
- Want zero auth code to maintain
- Deploying to Azure Static Web Apps

**Use Stack 5 (JWT) when:**

- Custom authentication logic needed
- Non-Azure deployments
- Want full control over auth flow
- Need custom user management

## References

- [SWA Authentication Docs](https://learn.microsoft.com/azure/static-web-apps/authentication-authorization)
- [SWA CLI Auth Emulation](https://azure.github.io/static-web-apps-cli/docs/cli/swa-login)
- [staticwebapp.config.json Reference](https://learn.microsoft.com/azure/static-web-apps/configuration)
