# Subnet Calculator - TypeScript + Vite Frontend

Modern single-page application (SPA) frontend for the subnet calculator, built with TypeScript, Vite, and Pico CSS.

## Architecture

- **Framework**: Vanilla TypeScript with Vite build tooling
- **UI Library**: Pico CSS v2 for modern, semantic styling
- **Testing**: Playwright for end-to-end browser testing
- **Linting/Formatting**: Biome for fast, consistent code quality
- **Container**: Multi-stage Docker build with nginx

## Features

- Modern TypeScript with strict type checking
- Fast development with Vite HMR (Hot Module Replacement)
- Responsive design with Pico CSS theming
- Comprehensive E2E tests with Playwright
- Production-ready nginx serving
- Zero vulnerabilities in container image (Alpine Linux base)

## Quick Start

### Local Development

```bash
# Install dependencies
npm install

# Start development server with HMR
npm run dev
# Access at http://localhost:5173

# Run type checking
npm run type-check

# Run linting
npm run lint

# Run tests (headless)
npm test

# Run tests (headed mode)
npm run test:headed

# Run tests (interactive UI)
npm run test:ui
```

### Docker/Podman Build

```bash
# Build the container image
podman build -t subnet-calculator-frontend-typescript-vite:latest .

# Run the container
podman run -d -p 3000:80 subnet-calculator-frontend-typescript-vite:latest

# Access at http://localhost:3000
```

### With Docker Compose

From the `subnet-calculator/` directory:

```bash
# Start TypeScript frontend with Container App API (Stack 4)
podman-compose up api-fastapi-container-app frontend-typescript-vite

# Access frontend at http://localhost:3000
# Access API docs at http://localhost:8090/api/v1/docs
```

## Development Workflow

### 1. Code

Edit files in `src/`:

- `src/main.ts` - Application entry point and logic
- `src/style.css` - Custom styles (extends Pico CSS)
- `index.html` - HTML template

### 2. Type Check

```bash
npm run type-check
```

### 3. Lint and Format

```bash
# Check for issues
npm run lint

# Auto-fix issues
npm run lint:fix

# Format code
npm run format

# Run all checks
npm run check
```

### 4. Test

```bash
# Run all Playwright tests
npm test

# Run tests in headed mode (see browser)
npm run test:headed

# Run tests in UI mode (interactive)
npm run test:ui
```

Tests are located in `tests/frontend.spec.ts` and cover:

- Page load and rendering
- IPv4 subnet calculations
- IPv6 subnet calculations
- Form validation
- Error handling

### 5. Build

```bash
# Build for production
npm run build

# Preview production build
npm run preview
```

Built files are output to `dist/`.

## Project Structure

```text
frontend-typescript-vite/
├── src/
│   ├── main.ts           # Application logic
│   ├── style.css         # Custom styles
│   └── vite-env.d.ts     # Vite type definitions
├── tests/
│   └── frontend.spec.ts  # Playwright E2E tests
├── index.html            # HTML template
├── nginx.conf            # nginx configuration for container
├── Dockerfile            # Multi-stage production build
├── package.json          # Dependencies and scripts
├── package-lock.json     # Locked dependencies
├── tsconfig.json         # TypeScript configuration
├── playwright.config.ts  # Playwright test configuration
├── biome.json           # Biome linter/formatter configuration
└── vite.config.ts       # Vite build configuration
```

## API Integration

The frontend communicates with the Container App API backend:

- **Development**: Configured in `vite.config.ts` to proxy `/api` to `http://localhost:8090`
- **Production**: nginx proxies `/api` requests to the backend service
- **Container**: Uses `api-fastapi-container-app` service via Docker network

API endpoints used:

- `GET /api/v1/health` - Health check
- `POST /api/v1/subnets/calculate` - Calculate subnet details

## Testing

### Playwright Tests

Located in `tests/frontend.spec.ts`:

```typescript
test('calculates IPv4 subnet correctly', async ({ page }) => {
  await page.goto('/');
  await page.fill('input[name="network"]', '192.168.1.0/24');
  await page.selectOption('select[name="provider"]', 'standard');
  await page.click('button[type="submit"]');
  await expect(page.locator('.result')).toContainText('Network: 192.168.1.0/24');
});
```

### Running Tests

```bash
# Headless (CI mode)
npm test

# Headed (see browser)
npm run test:headed

# UI mode (interactive debugging)
npm run test:ui
```

### Test Configuration

Configured in `playwright.config.ts`:

- Base URL: `http://localhost:3000`
- Browsers: Chromium, Firefox, WebKit
- Screenshots on failure
- Trace on first retry

## Code Quality

### Biome

Fast, modern linter and formatter replacing ESLint + Prettier:

```bash
# Check for issues
npm run lint

# Auto-fix issues
npm run lint:fix

# Format code
npm run format
```

Configuration in `biome.json`:

- Strict linting rules
- Consistent formatting
- Import sorting
- No unused variables

### TypeScript

Strict type checking enabled in `tsconfig.json`:

```bash
npm run type-check
```

## Container Details

### Multi-stage Build

1. **Builder stage**: Node.js 22 Alpine, installs deps and builds app
2. **Production stage**: nginx Alpine, serves static files

### Security

- Based on `nginx:alpine` (Alpine 3.22.2)
- **0 HIGH/CRITICAL vulnerabilities** (verified with Trivy)
- Runs nginx as non-root user (default nginx behavior)
- Minimal attack surface

### nginx Configuration

Located in `nginx.conf`:

- Serves static files from `/usr/share/nginx/html`
- SPA routing: Falls back to `index.html` for all routes
- Gzip compression enabled
- API proxy to backend (in compose stack)

## Environment Variables

None required - API endpoint is configured at build time in `vite.config.ts` for development and `nginx.conf` for production.

## Stack 4 - TypeScript Vite + Container App

This frontend is part of Stack 4, the most modern architecture:

**Stack 4 Components:**

- **Frontend**: TypeScript + Vite SPA (this project)
- **Backend**: Container App API (`api-fastapi-container-app`)
- **Authentication**: None (local development)

**Access Points:**

- Frontend: <http://localhost:3000>
- API Docs: <http://localhost:8090/api/v1/docs>

**Why Stack 4?**

- Modern SPA architecture with client-side routing
- TypeScript for type safety
- Fast Vite build tooling
- Comprehensive E2E testing with Playwright
- Production-ready nginx serving
- Clean separation of frontend/backend concerns

## Comparison with Other Frontends

| Feature | TypeScript Vite | Flask | Static HTML |
|---------|----------------|-------|-------------|
| Language | TypeScript | Python | JavaScript |
| Architecture | SPA | Server-rendered | Client-side |
| Build Tool | Vite | None | None |
| Type Safety | Strong | None | None |
| Testing | Playwright E2E | pytest unit | None |
| HMR | Yes | No | No |
| Bundle Size | ~50KB | N/A | ~5KB |
| Learning Curve | Medium | Low | Low |

## Contributing

1. Make changes to `src/` files
2. Run `npm run check` to verify types and linting
3. Run `npm test` to verify tests pass
4. Build container: `podman build -t subnet-calculator-frontend-typescript-vite:latest .`
5. Run security scan: `make trivy-scan` from repo root

## Troubleshooting

### Port Already in Use

If port 3000 is in use:

```bash
# Find process using port 3000
lsof -i :3000

# Kill process
kill -9 <PID>
```

### Playwright Browsers Not Installed

```bash
npx playwright install
```

### Type Errors

```bash
# Clean and reinstall
rm -rf node_modules package-lock.json
npm install
```

### Container Build Fails

Ensure you have `package-lock.json`:

```bash
npm install  # Generates package-lock.json
```

## License

Part of the public-cloud-experiments repository.
