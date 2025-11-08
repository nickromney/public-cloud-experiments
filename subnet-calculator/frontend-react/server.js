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
  API_BASE_URL: process.env.API_BASE_URL || '',
  AUTH_METHOD: process.env.AUTH_METHOD || '',
  JWT_USERNAME: process.env.JWT_USERNAME || '',
  JWT_PASSWORD: process.env.JWT_PASSWORD || '',
};

console.log('Runtime Configuration:', {
  API_BASE_URL: runtimeConfig.API_BASE_URL,
  AUTH_METHOD: runtimeConfig.AUTH_METHOD,
  JWT_USERNAME: runtimeConfig.JWT_USERNAME ? '***' : '(not set)',
  JWT_PASSWORD: runtimeConfig.JWT_PASSWORD ? '***' : '(not set)',
});

// Read the index.html template once at startup
const indexPath = path.join(__dirname, 'dist', 'index.html');
let indexTemplate;
try {
  indexTemplate = fs.readFileSync(indexPath, 'utf-8');
} catch (error) {
  console.error('Failed to read index.html:', error);
  process.exit(1);
}

// Serve static assets (CSS, JS, images)
app.use(express.static(path.join(__dirname, 'dist')));

// All routes serve index.html with injected runtime config
app.use((_req, res) => {
  // Inject runtime configuration as a script tag before the closing </head>
  const configScript = `
    <script>
      window.RUNTIME_CONFIG = ${JSON.stringify(runtimeConfig)};
    </script>
  `;

  const html = indexTemplate.replace('</head>', `${configScript}</head>`);
  res.send(html);
});

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
