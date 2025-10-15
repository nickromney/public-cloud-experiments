export const API_CONFIG = {
  baseUrl: import.meta.env.VITE_API_URL !== undefined ? import.meta.env.VITE_API_URL : 'http://localhost:8090',
  auth: {
    enabled: import.meta.env.VITE_AUTH_ENABLED === 'true',
    username: import.meta.env.VITE_JWT_USERNAME || '',
    password: import.meta.env.VITE_JWT_PASSWORD || '',
  },
  paths: {
    health: '/api/v1/health',
    // Both backends use consistent /ipv4/ endpoints
    validate: '/api/v1/ipv4/validate',
    checkPrivate: '/api/v1/ipv4/check-private',
    checkCloudflare: '/api/v1/ipv4/check-cloudflare',
    subnetInfo: '/api/v1/ipv4/subnet-info',
  },
}

/**
 * Get stack description based on API URL and auth configuration
 */
export function getStackDescription(): string {
  const isAuthEnabled = API_CONFIG.auth.enabled
  const apiUrl = API_CONFIG.baseUrl

  // Check for Azure Function indicators
  const isAzureFunction =
    apiUrl.includes(':7071') || apiUrl.includes(':8080') || (isAuthEnabled && (apiUrl === '' || apiUrl === '/'))

  if (isAzureFunction && isAuthEnabled) {
    return 'TypeScript + Vite + Azure Function (JWT)'
  }

  if (isAzureFunction) {
    return 'TypeScript + Vite + Azure Function'
  }

  return 'TypeScript + Vite + Container App'
}
