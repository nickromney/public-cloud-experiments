/**
 * Type definitions for API responses and application state
 */

export interface HealthResponse {
  status: string
  service: string
  version: string
}

export interface ValidateResponse {
  valid: boolean
  type: 'address' | 'network'
  address: string
  network_address?: string
  netmask?: string
  prefix_length?: number
  num_addresses?: number
  is_ipv4: boolean
  is_ipv6: boolean
}

export interface PrivateCheckResponse {
  address: string
  is_rfc1918: boolean
  is_rfc6598: boolean
  matched_rfc1918_range?: string
  matched_rfc6598_range?: string
}

export interface CloudflareCheckResponse {
  address: string
  is_cloudflare: boolean
  ip_version: number
  matched_ranges?: string[]
}

export interface SubnetInfoResponse {
  network: string
  mode: string
  network_address: string
  broadcast_address: string | null
  netmask: string
  wildcard_mask: string
  prefix_length: number
  total_addresses: number
  usable_addresses: number
  first_usable_ip: string
  last_usable_ip: string
  note?: string
}

export interface ApiResults {
  validate?: ValidateResponse
  private?: PrivateCheckResponse
  cloudflare?: CloudflareCheckResponse
  subnet?: SubnetInfoResponse
}

export interface ApiCallTiming {
  call: string
  requestTime: string
  responseTime: string
  duration: number
}

export interface PerformanceTiming {
  overallDuration: number
  renderingDuration: number
  totalDuration: number
  apiCalls: ApiCallTiming[]
}

export interface LookupResult {
  results: ApiResults
  timing: PerformanceTiming
}

export interface UserInfo {
  name?: string
  email?: string
  username?: string
}

export type CloudMode = 'standard' | 'simple' | 'expert'
