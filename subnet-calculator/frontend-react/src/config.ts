/**
 * Runtime configuration for the React frontend
 * Supports multiple deployment scenarios:
 * - Azure Web App with Easy Auth
 * - Azure Container Apps with Easy Auth
 * - Azure Static Web Apps with Entra ID
 * - AKS with OAuth2 Proxy sidecar
 * - Local development with MSAL
 */

// Runtime configuration (injected by deployment scripts or environment variables)
declare global {
  interface Window {
    RUNTIME_CONFIG?: {
      API_BASE_URL?: string
      AUTH_METHOD?: 'none' | 'easyauth' | 'msal' | 'entraid-swa' | 'jwt'
      AZURE_CLIENT_ID?: string
      AZURE_TENANT_ID?: string
      AZURE_REDIRECT_URI?: string
      JWT_USERNAME?: string
      JWT_PASSWORD?: string
    }
  }
}

export interface AuthConfig {
  method: 'none' | 'easyauth' | 'msal' | 'entraid-swa' | 'jwt'
  clientId?: string
  tenantId?: string
  redirectUri?: string
  jwtUsername?: string
  jwtPassword?: string
}

export interface AppConfig {
  apiBaseUrl: string
  auth: AuthConfig
  stackName: string
}

/**
 * Detect if running in Azure with Easy Auth enabled
 * Easy Auth sets WEBSITE_HOSTNAME environment variable
 */
export function isAzureEasyAuth(): boolean {
  // Check for Easy Auth headers (presence indicates Easy Auth is active)
  // This would be checked per-request in components
  return (
    typeof window !== 'undefined' &&
    (window.location.hostname.endsWith('.azurewebsites.net') ||
      window.location.hostname.endsWith('.azurecontainerapps.io'))
  )
}

/**
 * Detect if running in Azure Static Web Apps
 */
export function isAzureSWA(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Get authentication method based on environment
 * Priority: Runtime config > URL detection > Environment variables > Default
 */
export function getAuthMethod(): AuthConfig['method'] {
  // Check runtime config first (injected by deployment scripts)
  if (window.RUNTIME_CONFIG?.AUTH_METHOD) {
    console.log('Using runtime config AUTH_METHOD:', window.RUNTIME_CONFIG.AUTH_METHOD)
    return window.RUNTIME_CONFIG.AUTH_METHOD
  }

  // Check build-time environment variables
  const envAuthMethod = import.meta.env.VITE_AUTH_METHOD as AuthConfig['method'] | undefined
  if (envAuthMethod) {
    return envAuthMethod
  }

  // Auto-detect based on hostname
  if (isAzureSWA()) {
    return 'entraid-swa'
  }

  if (isAzureEasyAuth()) {
    return 'easyauth'
  }

  // Check if JWT credentials are available
  const jwtUsername = import.meta.env.VITE_JWT_USERNAME
  if (jwtUsername) {
    return 'jwt'
  }

  // Check if MSAL config is available for local development
  const clientId = import.meta.env.VITE_AZURE_CLIENT_ID
  if (clientId) {
    return 'msal'
  }

  // Default: no authentication
  return 'none'
}

/**
 * Get complete application configuration
 */
export function getAppConfig(): AppConfig {
  const authMethod = getAuthMethod()

  // API Base URL priority: Runtime > Window > Environment > Default (relative for SWA)
  const apiBaseUrl =
    window.RUNTIME_CONFIG?.API_BASE_URL || import.meta.env.VITE_API_URL || (isAzureSWA() ? '' : 'http://localhost:7071')

  // MSAL configuration (only used when authMethod === 'msal')
  const clientId = window.RUNTIME_CONFIG?.AZURE_CLIENT_ID || import.meta.env.VITE_AZURE_CLIENT_ID || ''

  const tenantId = window.RUNTIME_CONFIG?.AZURE_TENANT_ID || import.meta.env.VITE_AZURE_TENANT_ID || 'common'

  const redirectUri =
    window.RUNTIME_CONFIG?.AZURE_REDIRECT_URI || import.meta.env.VITE_AZURE_REDIRECT_URI || window.location.origin

  // JWT configuration (only used when authMethod === 'jwt')
  const jwtUsername = window.RUNTIME_CONFIG?.JWT_USERNAME || import.meta.env.VITE_JWT_USERNAME || ''
  const jwtPassword = window.RUNTIME_CONFIG?.JWT_PASSWORD || import.meta.env.VITE_JWT_PASSWORD || ''

  // Determine stack name for display
  let stackName = 'React + TypeScript + Vite'
  if (authMethod === 'easyauth') {
    stackName += ' + Azure Web App (Easy Auth)'
  } else if (authMethod === 'entraid-swa') {
    stackName += ' + Static Web Apps (Entra ID)'
  } else if (authMethod === 'msal') {
    stackName += ' (MSAL Local Dev)'
  } else if (authMethod === 'jwt') {
    stackName += ' + Azure Function (JWT)'
  }

  return {
    apiBaseUrl,
    auth: {
      method: authMethod,
      clientId,
      tenantId,
      redirectUri,
      jwtUsername,
      jwtPassword,
    },
    stackName,
  }
}

// Export lazy-loaded singleton config instance
let _cachedConfig: AppConfig | null = null

export function getConfig(): AppConfig {
  if (!_cachedConfig) {
    // Priority: window.RUNTIME_CONFIG (injected by server.js) > build-time env > defaults
    const authMethod = (window.RUNTIME_CONFIG?.AUTH_METHOD || getAuthMethod()) as AuthConfig['method']

    const apiBaseUrl =
      window.RUNTIME_CONFIG?.API_BASE_URL ||
      import.meta.env.VITE_API_URL ||
      (isAzureSWA() ? '' : 'http://localhost:7071')

    _cachedConfig = {
      apiBaseUrl,
      auth: {
        method: authMethod,
        clientId: window.RUNTIME_CONFIG?.AZURE_CLIENT_ID || import.meta.env.VITE_AZURE_CLIENT_ID || '',
        tenantId: window.RUNTIME_CONFIG?.AZURE_TENANT_ID || import.meta.env.VITE_AZURE_TENANT_ID || 'common',
        redirectUri: window.RUNTIME_CONFIG?.AZURE_REDIRECT_URI || import.meta.env.VITE_AZURE_REDIRECT_URI || window.location.origin,
        jwtUsername: window.RUNTIME_CONFIG?.JWT_USERNAME || import.meta.env.VITE_JWT_USERNAME || '',
        jwtPassword: window.RUNTIME_CONFIG?.JWT_PASSWORD || import.meta.env.VITE_JWT_PASSWORD || '',
      },
      stackName: `React + TypeScript + Vite${authMethod === 'jwt' ? ' + JWT' : authMethod === 'easyauth' ? ' + Easy Auth' : authMethod === 'entraid-swa' ? ' + SWA' : ''}`,
    }

    // Config initialized successfully
  }
  return _cachedConfig
}

// For backward compatibility
export const APP_CONFIG = new Proxy({} as AppConfig, {
  get(_target, prop) {
    return getConfig()[prop as keyof AppConfig]
  },
})
