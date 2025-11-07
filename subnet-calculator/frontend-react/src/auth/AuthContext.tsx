/**
 * Unified Authentication Context
 * Provides authentication state and methods for all auth providers:
 * - Easy Auth (Azure Web App / Container Apps)
 * - MSAL (Local development)
 * - Static Web Apps (Entra ID via SWA)
 * - None (no authentication)
 */

import { useMsal } from '@azure/msal-react'
import type React from 'react'
import { createContext, useContext, useEffect, useState } from 'react'
import { APP_CONFIG } from '../config'
import type { UserInfo } from '../types'
import { easyAuthLogin, easyAuthLogout, getEasyAuthUser, isEasyAuthAuthenticated } from './easyAuthProvider'
import { loginRequest } from './msalConfig'

interface AuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  login: () => void
  logout: () => void
  authMethod: string
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<UserInfo | null>(null)

  const authMethod = APP_CONFIG.auth.method

  // MSAL hooks - must always call hooks unconditionally (React rules)
  // When not using MSAL, instance will be null but hook must still be called
  const msalResult = useMsal()
  const instance = authMethod === 'msal' ? msalResult.instance : null
  const accounts = authMethod === 'msal' ? msalResult.accounts : []

  // Initialize authentication based on method
  useEffect(() => {
    const initAuth = async () => {
      setIsLoading(true)

      try {
        switch (authMethod) {
          case 'easyauth': {
            // Easy Auth - check /.auth/me endpoint
            const authenticated = await isEasyAuthAuthenticated()
            setIsAuthenticated(authenticated)

            if (authenticated) {
              const userInfo = await getEasyAuthUser()
              setUser(userInfo)
            }
            break
          }

          case 'msal': {
            // MSAL - check for active account
            if (accounts && accounts.length > 0) {
              setIsAuthenticated(true)
              const account = accounts[0]
              setUser({
                name: account.name || account.username,
                email: account.username,
                username: account.username,
              })
            }
            break
          }

          case 'entraid-swa': {
            // Static Web Apps - check /.auth/me endpoint (same as Easy Auth)
            const authenticated = await isEasyAuthAuthenticated()
            setIsAuthenticated(authenticated)

            if (authenticated) {
              const userInfo = await getEasyAuthUser()
              setUser(userInfo)
            }
            break
          }
          default:
            // No authentication
            setIsAuthenticated(true) // Allow access without auth
            break
        }
      } catch (error) {
        console.error('Auth initialization error:', error)
        setIsAuthenticated(false)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [authMethod, accounts])

  const login = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogin()
        break

      case 'msal':
        if (instance) {
          instance.loginRedirect(loginRequest)
        }
        break
      default:
        // No-op
        break
    }
  }

  const logout = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogout()
        break

      case 'msal':
        if (instance) {
          instance.logoutRedirect()
        }
        break
      default:
        // No-op
        break
    }
  }

  const value: AuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    login,
    logout,
    authMethod,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
