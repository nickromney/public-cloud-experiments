/**
 * API Client for subnet calculator
 * Supports both IPv4 and IPv6 lookups with performance timing
 */

import { APP_CONFIG } from '../config'
import type {
  ApiCallTiming,
  CloudflareCheckResponse,
  CloudMode,
  HealthResponse,
  LookupResult,
  PrivateCheckResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from '../types'

class ApiClient {
  private baseUrl: string

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl
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
    } catch (_error) {
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

  /**
   * Detect if address is IPv6
   */
  private isIpv6(address: string): boolean {
    return address.includes(':')
  }

  /**
   * Get API path prefix based on IP version
   */
  private getApiPrefix(address: string): string {
    return this.isIpv6(address) ? '/api/v1/ipv6' : '/api/v1/ipv4'
  }

  async checkHealth(): Promise<HealthResponse> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/health`, {
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
      const apiPrefix = this.getApiPrefix(address)
      const response = await fetch(`${this.baseUrl}${apiPrefix}/validate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000), // 10 second timeout
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return this.parseJsonResponse<ValidateResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async checkPrivate(address: string): Promise<PrivateCheckResponse> {
    try {
      const response = await fetch(`${this.baseUrl}/api/v1/ipv4/check-private`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return this.parseJsonResponse<PrivateCheckResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
    try {
      const apiPrefix = this.getApiPrefix(address)
      const response = await fetch(`${this.baseUrl}${apiPrefix}/check-cloudflare`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return this.parseJsonResponse<CloudflareCheckResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  async getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse> {
    try {
      const apiPrefix = this.getApiPrefix(network)
      const response = await fetch(`${this.baseUrl}${apiPrefix}/subnet-info`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ network, mode }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return this.parseJsonResponse<SubnetInfoResponse>(response)
    } catch (error) {
      return this.handleFetchError(error)
    }
  }

  /**
   * Perform complete lookup with timing information
   */
  async performLookup(address: string, mode: CloudMode): Promise<LookupResult> {
    const overallStart = performance.now()
    const apiCalls: ApiCallTiming[] = []
    const results: LookupResult['results'] = {}

    const isIpv6 = this.isIpv6(address)

    // 1. Validate address
    const validateStart = performance.now()
    const validateRequestTime = new Date().toISOString()
    results.validate = await this.validateAddress(address)
    const validateDuration = performance.now() - validateStart
    apiCalls.push({
      call: 'validate',
      requestTime: validateRequestTime,
      responseTime: new Date().toISOString(),
      duration: Math.round(validateDuration),
    })

    // 2. Check if RFC1918 (private) - IPv4 only
    if (!isIpv6) {
      const privateStart = performance.now()
      const privateRequestTime = new Date().toISOString()
      results.private = await this.checkPrivate(address)
      const privateDuration = performance.now() - privateStart
      apiCalls.push({
        call: 'checkPrivate',
        requestTime: privateRequestTime,
        responseTime: new Date().toISOString(),
        duration: Math.round(privateDuration),
      })
    }

    // 3. Check if Cloudflare
    const cloudflareStart = performance.now()
    const cloudflareRequestTime = new Date().toISOString()
    results.cloudflare = await this.checkCloudflare(address)
    const cloudflareDuration = performance.now() - cloudflareStart
    apiCalls.push({
      call: 'checkCloudflare',
      requestTime: cloudflareRequestTime,
      responseTime: new Date().toISOString(),
      duration: Math.round(cloudflareDuration),
    })

    // 4. Get subnet info if it's a network
    if (results.validate.type === 'network') {
      const subnetStart = performance.now()
      const subnetRequestTime = new Date().toISOString()
      results.subnet = await this.getSubnetInfo(address, mode)
      const subnetDuration = performance.now() - subnetStart
      apiCalls.push({
        call: 'subnetInfo',
        requestTime: subnetRequestTime,
        responseTime: new Date().toISOString(),
        duration: Math.round(subnetDuration),
      })
    }

    const overallDuration = performance.now() - overallStart

    return {
      results,
      timing: {
        overallDuration: Math.round(overallDuration),
        renderingDuration: 0, // Will be calculated by UI
        totalDuration: Math.round(overallDuration),
        apiCalls,
      },
    }
  }
}

// Export singleton instance
export const apiClient = new ApiClient(APP_CONFIG.apiBaseUrl)
