/**
 * API client for subnet calculator
 */

import { TokenManager } from './auth'
import { API_CONFIG } from './config'
import type {
  ApiResults,
  CloudflareCheckResponse,
  HealthResponse,
  PrivateCheckResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from './types'

class ApiClient {
  private baseUrl: string
  private tokenManager: TokenManager | null

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl

    // Initialize TokenManager if auth is enabled
    if (API_CONFIG.auth.enabled) {
      this.tokenManager = new TokenManager(baseUrl, API_CONFIG.auth.username, API_CONFIG.auth.password)
    } else {
      this.tokenManager = null
    }
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  /**
   * Safely parse JSON response with proper error handling
   */
  private async parseJsonResponse<T>(response: Response): Promise<T> {
    const contentType = response.headers.get('content-type')
    if (!contentType || !contentType.includes('application/json')) {
      throw new Error('API did not return JSON response. It may still be starting up.')
    }

    try {
      return await response.json()
    } catch (error) {
      throw new Error('Failed to parse API response. The API may be starting up or in an error state.')
    }
  }

  /**
   * Handle fetch errors with user-friendly messages
   */
  private handleFetchError(error: unknown): never {
    if (error instanceof Error) {
      if (error.name === 'TimeoutError' || error.name === 'AbortError') {
        throw new Error('API request timed out. The API may be starting up or unavailable.')
      }
      if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
        throw new Error('Unable to connect to API. Please ensure the backend is running.')
      }
    }
    throw error
  }

  async checkHealth(): Promise<HealthResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.health}`, {
        headers: {
          ...authHeaders,
        },
        signal: AbortSignal.timeout(5000), // 5 second timeout
      })

      if (!response.ok) {
        throw new Error(`API returned HTTP ${response.status}: ${response.statusText}`)
      }

      return this.parseJsonResponse<HealthResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async validateAddress(address: string): Promise<ValidateResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.validate}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000), // 10 second timeout
      })

      if (!response.ok) {
        const error = await this.parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Validation failed (HTTP ${response.status})`)
      }

      return this.parseJsonResponse<ValidateResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async checkPrivate(address: string): Promise<PrivateCheckResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkPrivate}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const error = await this.parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Private check failed (HTTP ${response.status})`)
      }

      return this.parseJsonResponse<PrivateCheckResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkCloudflare}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const error = await this.parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Cloudflare check failed (HTTP ${response.status})`)
      }

      return this.parseJsonResponse<CloudflareCheckResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async getSubnetInfo(network: string, mode: string): Promise<SubnetInfoResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.subnetInfo}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: JSON.stringify({ network, mode }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const error = await this.parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Subnet info failed (HTTP ${response.status})`)
      }

      return this.parseJsonResponse<SubnetInfoResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async performLookup(address: string, mode: string): Promise<ApiResults> {
    const results: ApiResults = {}

    // Validate
    results.validate = await this.validateAddress(address)

    // Check if private
    try {
      results.private = await this.checkPrivate(address)
    } catch (e) {
      // IPv6 addresses don't support this endpoint
      console.log('Private check skipped:', e)
    }

    // Check if Cloudflare
    results.cloudflare = await this.checkCloudflare(address)

    // Get subnet info if it's a network
    if (results.validate.type === 'network') {
      results.subnet = await this.getSubnetInfo(address, mode)
    }

    return results
  }
}

export const apiClient = new ApiClient(API_CONFIG.baseUrl)
