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
 * Check if we're running in Azure Static Web Apps
 */
export function isRunningInSWA(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Determine which auth method is active
 */
export function getAuthMethod(): 'none' | 'jwt' | 'entraid' {
  if (!API_CONFIG.auth.enabled) {
    return 'none'
  }

  // In SWA context, use Entra ID
  if (isRunningInSWA()) {
    return 'entraid'
  }

  // Otherwise use JWT (for local development with Azure Function)
  return 'jwt'
}

/**
 * Get stack description based on API URL and auth configuration
 */
export function getStackDescription(): string {
  const authMethod = getAuthMethod()
  const apiUrl = API_CONFIG.baseUrl

  // Check for Azure Function indicators (relative paths or specific ports)
  const isAzureFunction = apiUrl === '' || apiUrl === '/' || apiUrl.includes(':7071') || apiUrl.includes(':8080')

  // When running in SWA with Entra ID
  if (authMethod === 'entraid') {
    return 'TypeScript + Vite + SWA (Entra ID)'
  }

  if (isAzureFunction && authMethod === 'jwt') {
    return 'TypeScript + Vite + Azure Function (JWT)'
  }

  if (isAzureFunction) {
    return 'TypeScript + Vite + Azure Function'
  }

  return 'TypeScript + Vite + Container App'
}
