/**
 * API Configuration
 */

interface ApiConfig {
  baseUrl: string
  paths: {
    health: string
    validate: string
    checkPrivate: string
    checkCloudflare: string
    subnetInfo: string
  }
}

export const API_CONFIG: ApiConfig = {
  // Use environment variable or default to nginx proxy (empty = relative URLs)
  // In production (Docker): nginx proxies /api/* to backend
  // In development: can set VITE_API_BASE_URL to http://localhost:8090/api/v1
  baseUrl: import.meta.env.VITE_API_BASE_URL || '/api/v1',
  paths: {
    health: '/health',
    validate: '/ipv4/validate',
    checkPrivate: '/ipv4/check-private',
    checkCloudflare: '/ipv4/check-cloudflare',
    subnetInfo: '/ipv4/subnet-info',
  },
}
