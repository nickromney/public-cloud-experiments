/**
 * OIDC Authentication Provider
 * Uses oidc-client-ts for OpenID Connect authentication (Keycloak, Auth0, Okta, etc.)
 */

import type { UserInfo } from '@subnet-calculator/shared-frontend'
import { type ReactNode, createContext, useContext, useEffect, useState } from 'react'
import { UserManager, WebStorageStateStore } from 'oidc-client-ts'
import { APP_CONFIG } from '../config'

// Constants
const POST_LOGOUT_PAGE = '/logged-out.html'

interface OidcAuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  login: () => Promise<void>
  logout: () => void
}

const OidcAuthContext = createContext<OidcAuthContextType | undefined>(undefined)

// Initialize UserManager
let userManager: UserManager | null = null

function getUserManager(): UserManager {
  if (!userManager) {
    const authority = APP_CONFIG.auth.oidcAuthority
    const clientId = APP_CONFIG.auth.oidcClientId
    const redirectUri = APP_CONFIG.auth.oidcRedirectUri || window.location.origin

    if (!authority || !clientId) {
      throw new Error('OIDC configuration missing: authority and clientId required')
    }

    userManager = new UserManager({
      authority,
      client_id: clientId,
      redirect_uri: `${redirectUri}/`,
      post_logout_redirect_uri: `${redirectUri}${POST_LOGOUT_PAGE}`,
      response_type: 'code',
      scope: 'openid user_impersonation',
      automaticSilentRenew: true,
      userStore: new WebStorageStateStore({ store: window.localStorage }),
      // For local development with Keycloak
      loadUserInfo: true,
      metadata: {
        issuer: authority,
        authorization_endpoint: `${authority}/protocol/openid-connect/auth`,
        token_endpoint: `${authority}/protocol/openid-connect/token`,
        userinfo_endpoint: `${authority}/protocol/openid-connect/userinfo`,
        end_session_endpoint: `${authority}/protocol/openid-connect/logout`,
        jwks_uri: `${authority}/protocol/openid-connect/certs`,
      },
    })
  }

  return userManager
}

export function OidcAuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<UserInfo | null>(null)

  useEffect(() => {
    const initAuth = async () => {
      try {
        const manager = getUserManager()

        // Handle redirect from OIDC provider
        if (window.location.search.includes('code=') || window.location.search.includes('state=')) {
          try {
            const oidcUser = await manager.signinRedirectCallback()
            setIsAuthenticated(true)
            setUser({
              name: oidcUser.profile.name || oidcUser.profile.preferred_username || 'Unknown',
              email: oidcUser.profile.email || '',
              username: oidcUser.profile.preferred_username || oidcUser.profile.sub || '',
            })
            // Clean up URL
            window.history.replaceState({}, document.title, window.location.pathname)
          } catch (error) {
            console.error('Error handling OIDC callback:', error)
          }
        } else {
          // Check if user is already authenticated
          const oidcUser = await manager.getUser()
          if (oidcUser && !oidcUser.expired) {
            setIsAuthenticated(true)
            setUser({
              name: oidcUser.profile.name || oidcUser.profile.preferred_username || 'Unknown',
              email: oidcUser.profile.email || '',
              username: oidcUser.profile.preferred_username || oidcUser.profile.sub || '',
            })
          }
        }
      } catch (error) {
        console.error('OIDC initialization error:', error)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [])

  const login = async () => {
    const manager = getUserManager()
    await manager.signinRedirect()
  }

  const logout = () => {
    const manager = getUserManager()
    manager.signoutRedirect()
  }

  const value: OidcAuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    login,
    logout,
  }

  return <OidcAuthContext.Provider value={value}>{children}</OidcAuthContext.Provider>
}

export function useOidcAuth() {
  const context = useContext(OidcAuthContext)
  if (context === undefined) {
    throw new Error('useOidcAuth must be used within an OidcAuthProvider')
  }
  return context
}

// Get access token for API calls
export async function getOidcAccessToken(): Promise<string | null> {
  try {
    const manager = getUserManager()
    const user = await manager.getUser()

    if (!user || user.expired) {
      return null
    }

    return user.access_token
  } catch (error) {
    console.error('Error getting OIDC access token:', error)
    return null
  }
}
