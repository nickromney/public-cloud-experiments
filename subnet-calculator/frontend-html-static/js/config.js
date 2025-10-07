/**
 * API Configuration
 *
 * This file contains the API endpoint configuration. Update the API_BASE_URL
 * for different deployment environments:
 *
 * Local Development:
 *   - Docker Compose: 'http://localhost:8080'
 *   - Azure Functions: 'http://localhost:7071'
 *
 * Production:
 *   - Azure Functions: 'https://your-function-app.azurewebsites.net'
 *   - Azure API Management: 'https://your-apim.azure-api.net'
 *
 * CORS Note:
 *   The API is configured with CORS enabled (Access-Control-Allow-Origin: *)
 *   in host.json. For production, update to specific allowed origins.
 */

const API_CONFIG = {
  // Default: Use Docker Compose API endpoint
  BASE_URL: "http://localhost:7071",

  // API paths
  PATHS: {
    HEALTH: "/api/v1/health",
    VALIDATE: "/api/v1/ipv4/validate",
    CHECK_PRIVATE: "/api/v1/ipv4/check-private",
    CHECK_CLOUDFLARE: "/api/v1/ipv4/check-cloudflare",
    SUBNET_INFO: "/api/v1/ipv4/subnet-info",
  },
};

// Override BASE_URL from environment variable if available
// (Used when deploying to static hosting platforms)
if (typeof window !== "undefined" && window.API_BASE_URL) {
  API_CONFIG.BASE_URL = window.API_BASE_URL;
}
