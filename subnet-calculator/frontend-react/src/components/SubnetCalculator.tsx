/**
 * Main Subnet Calculator Component
 * Handles the complete subnet calculator UI and logic
 * Uses Pico CSS with minimal inline styles
 */

import { useState, useEffect } from 'react'
import { useAuth } from '../auth/AuthContext'
import { apiClient } from '../api/client'
import { APP_CONFIG } from '../config'
import type { CloudMode, LookupResult, HealthResponse } from '../types'

interface SubnetCalculatorProps {
  theme: 'light' | 'dark'
  onToggleTheme: () => void
}

export function SubnetCalculator({ theme, onToggleTheme }: SubnetCalculatorProps) {
  const { user, isAuthenticated, isLoading: authLoading, login, logout } = useAuth()

  const [ipAddress, setIpAddress] = useState('')
  const [cloudMode, setCloudMode] = useState<CloudMode>('standard')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [results, setResults] = useState<LookupResult | null>(null)
  const [apiHealth, setApiHealth] = useState<HealthResponse | null>(null)
  const [apiError, setApiError] = useState<string | null>(null)

  // Check API health on mount
  useEffect(() => {
    const checkHealth = async () => {
      try {
        const health = await apiClient.checkHealth()
        setApiHealth(health)
        setApiError(null)
      } catch (err) {
        setApiError(err instanceof Error ? err.message : 'API unavailable')
      }
    }

    checkHealth()
  }, [])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsLoading(true)
    setError(null)
    setResults(null)

    try {
      const result = await apiClient.performLookup(ipAddress, cloudMode)
      setResults(result)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    } finally {
      setIsLoading(false)
    }
  }

  const handleExampleClick = (address: string) => {
    setIpAddress(address)
  }

  if (authLoading) {
    return (
      <div className="container loading-center">
        <div aria-busy="true">Loading...</div>
      </div>
    )
  }

  return (
    <>
      {/* Top Bar - Fixed Position */}
      <div className="top-bar">
        <button type="button" onClick={onToggleTheme}>
          <span>{theme === 'dark' ? '☀️' : '🌙'}</span> Toggle Theme
        </button>
        {isAuthenticated && user && (
          <div className="user-info">
            <span>Welcome, {user.name}</span>
            <button type="button" onClick={logout}>
              Logout
            </button>
          </div>
        )}
        {!isAuthenticated && APP_CONFIG.auth.method !== 'none' && (
          <button type="button" onClick={login}>
            Login
          </button>
        )}
      </div>

      <main className="container">
        {/* Header */}
        <header>
          <h1>IPv4 & IPv6 Subnet Calculator</h1>
          <p>{APP_CONFIG.stackName}</p>
        </header>

        {/* API Status */}
        {apiHealth && (
          <div className="alert alert-success" role="status">
            <strong>API Connected:</strong> {apiHealth.service} v{apiHealth.version}
          </div>
        )}
        {apiError && (
          <div className="alert alert-error" role="alert">
            <strong>API Offline:</strong> {apiError}
          </div>
        )}

        {/* Input Form */}
        <section>
          <form onSubmit={handleSubmit}>
            <div>
              <label htmlFor="ip-address">IP Address or CIDR Range</label>
              <div className="form-row">
                <input
                  type="text"
                  id="ip-address"
                  value={ipAddress}
                  onChange={e => setIpAddress(e.target.value)}
                  placeholder="e.g., 192.168.1.1 or 10.0.0.0/24"
                  required
                />
                <select
                  id="cloud-mode"
                  value={cloudMode}
                  onChange={e => setCloudMode(e.target.value as CloudMode)}
                >
                  <option value="standard">Standard</option>
                  <option value="simple">Simple</option>
                  <option value="expert">Expert</option>
                </select>
                <button type="submit" disabled={isLoading || !ipAddress}>
                  Lookup
                </button>
              </div>
            </div>

            {/* Example Buttons */}
            <div className="example-buttons">
              <button type="button" className="secondary outline" onClick={() => handleExampleClick('10.0.0.0/24')}>
                RFC1918: 10.0.0.0/24
              </button>
              <button type="button" className="outline" onClick={() => handleExampleClick('8.8.8.8')}>
                Public: 8.8.8.8
              </button>
              <button type="button" className="contrast outline" onClick={() => handleExampleClick('104.16.1.1')}>
                Cloudflare: 104.16.1.1
              </button>
              <button type="button" className="secondary" onClick={() => handleExampleClick('2001:db8::/32')}>
                IPv6: 2001:db8::/32
              </button>
            </div>
          </form>
        </section>

        {/* Loading */}
        {isLoading && (
          <div className="loading-center" role="status">
            <div aria-busy="true">Loading...</div>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="alert alert-error" role="alert">
            <strong>Error:</strong> {error}
          </div>
        )}

        {/* Results */}
        {results && (
          <section data-testid="results">
            <h2>Results</h2>

            {/* Validation */}
            {results.results.validate && (
              <article>
                <h3>Validation</h3>
                <table>
                  <tbody>
                    <tr>
                      <td><strong>Valid</strong></td>
                      <td>{results.results.validate.valid ? 'Yes' : 'No'}</td>
                    </tr>
                    <tr>
                      <td><strong>Type</strong></td>
                      <td>{results.results.validate.type}</td>
                    </tr>
                    <tr>
                      <td><strong>Address</strong></td>
                      <td>{results.results.validate.address}</td>
                    </tr>
                    <tr>
                      <td><strong>IP Version</strong></td>
                      <td>{results.results.validate.is_ipv6 ? 'IPv6' : 'IPv4'}</td>
                    </tr>
                  </tbody>
                </table>
              </article>
            )}

            {/* Private Check (IPv4 only) */}
            {results.results.private && (
              <article>
                <h3>RFC1918 Private Address Check</h3>
                <table>
                  <tbody>
                    <tr>
                      <td><strong>Is RFC1918</strong></td>
                      <td>{results.results.private.is_rfc1918 ? 'Yes' : 'No'}</td>
                    </tr>
                    {results.results.private.matched_rfc1918_range && (
                      <tr>
                        <td><strong>Matched Range</strong></td>
                        <td>{results.results.private.matched_rfc1918_range}</td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </article>
            )}

            {/* Cloudflare Check */}
            {results.results.cloudflare && (
              <article>
                <h3>Cloudflare Check</h3>
                <table>
                  <tbody>
                    <tr>
                      <td><strong>Is Cloudflare</strong></td>
                      <td>{results.results.cloudflare.is_cloudflare ? 'Yes' : 'No'}</td>
                    </tr>
                    {results.results.cloudflare.matched_ranges &&
                      results.results.cloudflare.matched_ranges.length > 0 && (
                        <tr>
                          <td><strong>Matched Ranges</strong></td>
                          <td>{results.results.cloudflare.matched_ranges.join(', ')}</td>
                        </tr>
                      )}
                  </tbody>
                </table>
              </article>
            )}

            {/* Subnet Info */}
            {results.results.subnet && (
              <article>
                <h3>Subnet Information</h3>
                <table>
                  <tbody>
                    <tr>
                      <td><strong>Network</strong></td>
                      <td>{results.results.subnet.network}</td>
                    </tr>
                    <tr>
                      <td><strong>Network Address</strong></td>
                      <td>{results.results.subnet.network_address}</td>
                    </tr>
                    {results.results.subnet.broadcast_address && (
                      <tr>
                        <td><strong>Broadcast Address</strong></td>
                        <td>{results.results.subnet.broadcast_address}</td>
                      </tr>
                    )}
                    <tr>
                      <td><strong>Netmask</strong></td>
                      <td>{results.results.subnet.netmask}</td>
                    </tr>
                    <tr>
                      <td><strong>Prefix Length</strong></td>
                      <td>/{results.results.subnet.prefix_length}</td>
                    </tr>
                    <tr>
                      <td><strong>Total Addresses</strong></td>
                      <td>{results.results.subnet.total_addresses.toLocaleString()}</td>
                    </tr>
                    <tr>
                      <td><strong>Usable Addresses</strong></td>
                      <td>{results.results.subnet.usable_addresses.toLocaleString()}</td>
                    </tr>
                    <tr>
                      <td><strong>First Usable IP</strong></td>
                      <td>{results.results.subnet.first_usable_ip}</td>
                    </tr>
                    <tr>
                      <td><strong>Last Usable IP</strong></td>
                      <td>{results.results.subnet.last_usable_ip}</td>
                    </tr>
                  </tbody>
                </table>
              </article>
            )}

            {/* Performance Timing */}
            <article className="performance-timing">
              <h3>Performance Timing</h3>
              <table>
                <tbody>
                  <tr>
                    <td><strong>Total Response Time</strong></td>
                    <td>
                      <strong>{results.timing.totalDuration}ms</strong> (
                      {(results.timing.totalDuration / 1000).toFixed(3)}s)
                    </td>
                  </tr>
                </tbody>
              </table>

              {/* API Call Details */}
              <details>
                <summary>API Call Details</summary>
                <table>
                  <thead>
                    <tr>
                      <th>Call</th>
                      <th>Duration</th>
                      <th>Request Time (UTC)</th>
                      <th>Response Time (UTC)</th>
                    </tr>
                  </thead>
                  <tbody>
                    {results.timing.apiCalls.map((call, index) => (
                      <tr key={`${call.call}-${index}`}>
                        <td>{call.call}</td>
                        <td><strong>{call.duration}ms</strong></td>
                        <td>{new Date(call.requestTime).toLocaleString()}</td>
                        <td>{new Date(call.responseTime).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </details>
            </article>
          </section>
        )}
      </main>
    </>
  )
}
