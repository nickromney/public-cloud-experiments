import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 8080;

// Read runtime configuration from environment variables
const runtimeConfig = {
  apiBaseUrl: process.env.API_BASE_URL || '',
  authMethod: process.env.AUTH_METHOD || '',
  jwtUsername: process.env.JWT_USERNAME || '',
  jwtPassword: process.env.JWT_PASSWORD || '',
  azureClientId: process.env.AZURE_CLIENT_ID || '',
  azureTenantId: process.env.AZURE_TENANT_ID || '',
};

console.log('Runtime Configuration:', {
  apiBaseUrl: runtimeConfig.apiBaseUrl,
  authMethod: runtimeConfig.authMethod,
  jwtUsername: runtimeConfig.jwtUsername ? '***' : '(not set)',
  jwtPassword: runtimeConfig.jwtPassword ? '***' : '(not set)',
  azureClientId: runtimeConfig.azureClientId ? '***' : '(not set)',
  azureTenantId: runtimeConfig.azureTenantId || '(not set)',
});

// Serve static assets (CSS, JS, images) - but NOT index.html
app.use(express.static(path.join(__dirname, 'dist'), { index: false }));

// SPA fallback - inject runtime config into index.html (Express 5 compatible)
app.use((_req, res) => {
  const indexPath = path.join(__dirname, 'dist', 'index.html');
  let html = fs.readFileSync(indexPath, 'utf8');

  // Inject runtime config as inline script BEFORE other scripts
  const configScript = `
    <script>
      window.RUNTIME_CONFIG = {
        API_BASE_URL: '${runtimeConfig.apiBaseUrl}',
        AUTH_METHOD: '${runtimeConfig.authMethod}',
        JWT_USERNAME: '${runtimeConfig.jwtUsername}',
        JWT_PASSWORD: '${runtimeConfig.jwtPassword}'
      };
    </script>`;

  // Insert before closing </head> tag
  html = html.replace('</head>', `${configScript}</head>`);

  res.send(html);
});

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
