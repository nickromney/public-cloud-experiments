/**
 * API client for subnet calculator
 */

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

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  async checkHealth(): Promise<HealthResponse> {
    const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.health}`)
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }
    return response.json()
  }

  async validateAddress(address: string): Promise<ValidateResponse> {
    const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.validate}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ address }),
    })
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.detail || 'Validation failed')
    }
    return response.json()
  }

  async checkPrivate(address: string): Promise<PrivateCheckResponse> {
    const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkPrivate}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ address }),
    })
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.detail || 'Private check failed')
    }
    return response.json()
  }

  async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
    const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkCloudflare}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ address }),
    })
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.detail || 'Cloudflare check failed')
    }
    return response.json()
  }

  async getSubnetInfo(network: string, mode: string): Promise<SubnetInfoResponse> {
    const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.subnetInfo}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ network, mode }),
    })
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.detail || 'Subnet info failed')
    }
    return response.json()
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
