/**
 * Easy Auth Provider
 * Handles Azure App Service / Container Apps Easy Auth
 * Easy Auth injects user information via HTTP headers
 */

import type { UserInfo } from '../types'

export interface EasyAuthPrincipal {
  auth_typ?: string
  claims?: Array<{ typ: string; val: string }>
  name_typ?: string
  role_typ?: string
  userId?: string
  identityProvider?: string
}

/**
 * Parse Easy Auth principal from X-MS-CLIENT-PRINCIPAL header
 * This would typically be done server-side, but for client-side SPAs
 * we can make a call to /.auth/me endpoint
 */
export async function getEasyAuthUser(): Promise<UserInfo | null> {
  try {
    const response = await fetch('/.auth/me', {
      credentials: 'include',
    })

    if (!response.ok) {
      return null
    }

    const data = await response.json()

    // Easy Auth returns an array with user info
    if (!data || !Array.isArray(data) || data.length === 0) {
      return null
    }

    const principal = data[0]

    // Extract claims into a map for easier access
    const claims: Record<string, string> = {}
    if (principal.claims) {
      for (const claim of principal.claims) {
        claims[claim.typ] = claim.val
      }
    }

    // Extract user information
    return {
      name: claims.name || principal.user_id || 'User',
      email: claims.email || claims.preferred_username,
      username: principal.user_id,
    }
  } catch (error) {
    console.error('Error fetching Easy Auth user info:', error)
    return null
  }
}

/**
 * Check if user is authenticated with Easy Auth
 */
export async function isEasyAuthAuthenticated(): Promise<boolean> {
  const user = await getEasyAuthUser()
  return user !== null
}

/**
 * Initiate Easy Auth login
 */
export function easyAuthLogin(provider: string = 'aad'): void {
  window.location.href = `/.auth/login/${provider}?post_login_redirect_uri=${encodeURIComponent(window.location.href)}`
}

/**
 * Initiate Easy Auth logout
 */
export function easyAuthLogout(): void {
  window.location.href = `/.auth/logout?post_logout_redirect_uri=${encodeURIComponent(window.location.origin)}`
}
