import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createProxyMiddleware } from 'http-proxy-middleware';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 8080;

// Read runtime configuration from environment variables
const runtimeConfig = {
  API_BASE_URL: process.env.API_BASE_URL || '',
  AUTH_METHOD: process.env.AUTH_METHOD || process.env.AUTH_MODE || '',
  JWT_USERNAME: process.env.JWT_USERNAME || '',
  JWT_PASSWORD: process.env.JWT_PASSWORD || '',
  AZURE_CLIENT_ID: process.env.AZURE_CLIENT_ID || '',
  AZURE_TENANT_ID: process.env.AZURE_TENANT_ID || '',
  AZURE_REDIRECT_URI: process.env.AZURE_REDIRECT_URI || '',
  EASYAUTH_RESOURCE_ID: process.env.EASYAUTH_RESOURCE_ID || '',
};

const proxyTarget = process.env.PROXY_API_URL || '';
const forwardEasyAuthHeaders = process.env.PROXY_FORWARD_EASYAUTH_HEADERS !== 'false';
const easyAuthHeaderWhitelist = [
  'x-zumo-auth',
  'authorization',
  'x-ms-token-aad-access-token',
  'x-ms-token-aad-id-token',
  'x-ms-client-principal',
  'x-ms-client-principal-id',
  'x-ms-client-principal-name',
];

console.log('Runtime Configuration:', {
  API_BASE_URL: runtimeConfig.API_BASE_URL,
  AUTH_METHOD: runtimeConfig.AUTH_METHOD,
  JWT_USERNAME: runtimeConfig.JWT_USERNAME ? '***' : '(not set)',
  JWT_PASSWORD: runtimeConfig.JWT_PASSWORD ? '***' : '(not set)',
  AZURE_CLIENT_ID: runtimeConfig.AZURE_CLIENT_ID ? '***' : '(not set)',
  AZURE_TENANT_ID: runtimeConfig.AZURE_TENANT_ID || '(not set)',
  AZURE_REDIRECT_URI: runtimeConfig.AZURE_REDIRECT_URI || '(not set)',
  PROXY_API_URL: proxyTarget ? '(configured)' : '(disabled)',
  FORWARD_EASYAUTH_HEADERS: forwardEasyAuthHeaders,
});

if (proxyTarget) {
  console.log('Enabling API proxy middleware');
  app.use(
    '/api',
    createProxyMiddleware({
      target: proxyTarget,
      changeOrigin: true,
      logLevel: process.env.NODE_ENV === 'production' ? 'warn' : 'info',
      xfwd: true,
      onProxyReq: (proxyReq, req) => {
        if (!forwardEasyAuthHeaders) {
          return;
        }

        easyAuthHeaderWhitelist.forEach((header) => {
          const value = req.headers[header];
          if (value) {
            proxyReq.setHeader(header, value);
          }
        });
      },
    })
  );
}

// Serve static assets (CSS, JS, images) - but NOT index.html
app.use(express.static(path.join(__dirname, 'dist'), { index: false }));

// SPA fallback - inject runtime config into index.html (Express 5 compatible)
app.use((_req, res) => {
  const indexPath = path.join(__dirname, 'dist', 'index.html');
  let html = fs.readFileSync(indexPath, 'utf8');

  // Inject runtime config as inline script BEFORE other scripts
  // Use JSON.stringify to properly escape values and prevent XSS
  const configScript = `
    <script>
      window.RUNTIME_CONFIG = ${JSON.stringify(runtimeConfig)};
    </script>`;

  // Insert before closing </head> tag
  html = html.replace('</head>', `${configScript}</head>`);

  res.send(html);
});

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
