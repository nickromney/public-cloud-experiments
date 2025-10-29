# 60-entraid-user-setup.sh - Entra ID Configuration Script

This script automates the setup and troubleshooting of Entra ID app registrations for Azure Static Web App OAuth authentication.

## What It Does

The script handles all the necessary configurations **automatically**, including:

- Creates new app registrations from scratch
- Sets **web redirect URIs** (not SPA or public client)
- Creates client secrets with proper JSON output parsing
- Enables implicit grant settings (ID token + access token)
- Sets token version to 2 (required for SWA)
- Auto-detects SWA and updates app settings automatically
- Fixes redirect URIs on existing apps
- Creates new secrets when needed
- Grants admin consent (opens browser)
- Diagnoses configuration issues

## Quick Start

### Create Fresh App Registration (Fully Automated)

````bash
./60-entraid-user-setup.sh --create --app-name "My App" --swa-hostname "proud-bay-05b7e1c03.1.azurestaticapps.net"
```bash

This will:

1. Create the app registration
2. Generate a client secret
3. Set implicit grant + token version
4. Auto-detect SWA and update it with new credentials
5. Show you the credentials to save

### Diagnose Existing App

```bash
./60-entraid-user-setup.sh --diagnose --app-id <client-id>
```bash

Shows:

- / Redirect URIs configuration
- / Implicit grant settings
- / Token version
- / Public client status

### Fix Issues

```bash
# Fix redirect URIs
./60-entraid-user-setup.sh --fix-redirects --app-id <id> --swa-hostname <hostname>

# Create new secret
./60-entraid-user-setup.sh --new-secret --app-id <id>

# Grant admin consent
./60-entraid-user-setup.sh --admin-consent --app-id <id>
```bash

### Interactive Mode

```bash
./60-entraid-user-setup.sh
```bash

Prompts you through the process interactively.

## What Changed

### Previously Required Manual Steps

Before, you had to run extra commands after creating an app:

```bash
# OLD WAY - Multiple steps
./60-entraid-user-setup.sh --create ...
# Then manually:
az staticwebapp appsettings set ...
az rest --method PATCH ... --body '{"api":{"requestedAccessTokenVersion":2}}'
```bash

### Now Automated

```bash
# NEW WAY - Everything in one command
./60-entraid-user-setup.sh --create --app-name "My App" --swa-hostname "..."
# ✓ Creates app
# ✓ Creates secret
# ✓ Sets implicit grant
# ✓ Sets token version to 2
# ✓ Updates SWA automatically
```bash

## Script Fixes Applied

### 1. Correct Azure CLI Commands

- Changed `az ad app credential create` → `az ad app credential reset`
- Fixed JSON output field: `.secretText` → `.password`

### 2. Complete Configuration

- Added token version setting (was missing)
- Combined implicit grant + token version in one API call
- Now happens automatically during app creation

### 3. Auto-Detection

- Auto-detects SWA name and hostname from Azure
- Auto-detects resource group
- Auto-updates SWA settings without manual intervention

### 4. Better Error Handling

- Handles missing SWA gracefully
- Shows manual update command if auto-detection fails
- Displays credentials clearly for saving

## Usage Examples

### Example 1: Full Automated Setup

```bash
./60-entraid-user-setup.sh --create \
  --app-name "Subnet Calculator" \
  --swa-hostname "proud-bay-05b7e1c03.1.azurestaticapps.net"
```bash

**Output:**

```bash
[STEP] Creating new app registration
[INFO] Creating app: Subnet Calculator
[✓] App created: e61759a7-bb71-40cb-b373-bfc21b81b641
[✓] Secret created
[✓] Implicit grant enabled and token version set to 2
[✓] SWA updated with new credentials
[INFO] SAVE THESE VALUES:
CLIENT_ID: <REDACTED>
CLIENT_SECRET: <REDACTED>
TENANT_ID: <REDACTED>
```bash

### Example 2: Diagnose Issues

```bash
./60-entraid-user-setup.sh --diagnose --app-id <your-client-id>
```bash

**Output:**

```bash
[STEP] Running diagnostic checks
[INFO] App Registration Check:
  Display Name: Subnet Calc Fresh
  App ID: e61759a7-bb71-40cb-b373-bfc21b81b641

[INFO] Redirect URIs:
  ✓ Web: https://proud-bay-05b7e1c03.1.azurestaticapps.net/.auth/login/aad/callback
  ✓ Public Client: (empty)

[INFO] Implicit Grant Settings:
  ✓ ID Token Issuance: enabled
  ✓ Access Token Issuance: enabled

[INFO] Token Configuration:
  ✓ Token Version: 2

[✓] Configuration looks correct!
```bash

## All Commands

| Command           | Description                         |
| ----------------- | ----------------------------------- |
| `--create`        | Create new app registration         |
| `--fix-redirects` | Fix redirect URIs on existing app   |
| `--new-secret`    | Create new client secret            |
| `--admin-consent` | Grant admin consent (opens browser) |
| `--diagnose`      | Check configuration for issues      |

## All Options

| Option                  | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `--app-name <name>`     | Display name for app (for `--create`)        |
| `--swa-hostname <host>` | SWA hostname (auto-detected if not provided) |
| `--app-id <id>`         | Entra ID app registration client ID          |
| `--swa-name <name>`     | Static Web App name (auto-detected)          |
| `--user-upn <upn>`      | User principal name for testing              |
| `--verbose`             | Show detailed output                         |
| `--dry-run`             | Show what would be done (no changes)         |

## What Gets Configured

When you create an app registration, the script configures:

```bash
App Registration
├─ Display Name: Your app name
├─ Web Redirect URI: https://<swa-hostname>/.auth/login/aad/callback
├─ Implicit Grant
│  ├─ ID Token Issuance: ✓ Enabled
│  └─ Access Token Issuance: ✓ Enabled
├─ Token Version: 2
└─ Public Client: (empty - not needed for web apps)

SWA App Settings
├─ AZURE_CLIENT_ID: <your app id>
└─ AZURE_CLIENT_SECRET: <generated secret>
```

### About the Implicit Grant Warning

**You will see a warning in Azure Portal about implicit grant being enabled.** This is expected and correct.

Azure Portal Warning:
> "This app has implicit grant settings enabled. If you are using any of these URIs in a SPA with MSAL.js 2.0, you should migrate URIs."

**Why this warning doesn't apply to you:**

- Azure Static Web Apps uses **built-in platform authentication**, not MSAL.js
- SWA's auth uses `response_mode=form_post`, which **requires implicit grant** to be enabled
- Your URIs are registered as **Web platform** (not SPA platform), which is correct
- This is Microsoft's recommended configuration for SWA with Entra ID

**Action required:** None. The warning is for developers using MSAL.js directly in SPAs. You're using SWA's platform-level auth, which is the recommended approach.

**References:**
- [Azure Static Web Apps authentication](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization)
- [SWA Entra ID configuration](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-custom?tabs=aad)

## Troubleshooting

### "SWA not found"

- SWA auto-detection failed
- Provide `--swa-name` explicitly
- Or update SWA manually using the shown command

### "Configuration looks correct!" but login still fails

- Grant admin consent: `./60-entraid-user-setup.sh --admin-consent --app-id <id>`
- Clear browser cache thoroughly
- Try with a different browser

### Secret issues

- Create a new secret: `./60-entraid-user-setup.sh --new-secret --app-id <id>`
- Update SWA with new secret value

## Integration with Other Scripts

This script complements:

- `42-configure-entraid-swa.sh` - SWA configuration
- `64-verify-entraid-setup.sh` - Verification and diagnostics

## See Also

- [ENV-SETUP.md](./frontend-python-flask/ENV-SETUP.md) - Local environment setup
- [ENTRAID.md](./frontend-python-flask/ENTRAID.md) - Complete Entra ID guide
- [IMPLEMENTATION-SUMMARY.md](./frontend-python-flask/IMPLEMENTATION-SUMMARY.md) - Architecture overview
````
