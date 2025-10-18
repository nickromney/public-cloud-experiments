// Runtime configuration (injected by deployment scripts)
// Deployment scripts can set window.RUNTIME_CONFIG before loading this module
declare global {
  interface Window {
    API_BASE_URL?: string
    AUTH_ENABLED?: string
    JWT_USERNAME?: string
    JWT_PASSWORD?: string
  }
}

export const API_CONFIG = {
  // Priority: Runtime config (window) > Build-time env (import.meta.env) > Default (empty for SWA proxy)
  baseUrl: (typeof window !== 'undefined' && window.API_BASE_URL) || import.meta.env.VITE_API_URL || '',
  auth: {
    enabled:
      (typeof window !== 'undefined' && window.AUTH_ENABLED === 'true') || import.meta.env.VITE_AUTH_ENABLED === 'true',
    username: (typeof window !== 'undefined' && window.JWT_USERNAME) || import.meta.env.VITE_JWT_USERNAME || '',
    password: (typeof window !== 'undefined' && window.JWT_PASSWORD) || import.meta.env.VITE_JWT_PASSWORD || '',
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

  // Check for Azure Function indicators (relative paths or specific ports)
  const isAzureFunction = apiUrl === '' || apiUrl === '/' || apiUrl.includes(':7071') || apiUrl.includes(':8080')

  if (isAzureFunction && isAuthEnabled) {
    return 'TypeScript + Vite + Azure Function (JWT)'
  }

  if (isAzureFunction) {
    return 'TypeScript + Vite + Azure Function'
  }

  return 'TypeScript + Vite + Container App'
}
