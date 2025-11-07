/**
 * Main Subnet Calculator Component
 * Handles the complete subnet calculator UI and logic
 * Uses Pico CSS with minimal inline styles
 */

import { useEffect, useState } from 'react'
import { apiClient } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { APP_CONFIG } from '../config'
import type { CloudMode, HealthResponse, LookupResult } from '../types'

interface SubnetCalculatorProps {
  theme: 'light' | 'dark'
  onToggleTheme: () => void
}

export function SubnetCalculator({ theme, onToggleTheme }: SubnetCalculatorProps) {
  const { user, isAuthenticated, isLoading: authLoading, login, logout } = useAuth()

  const [ipAddress, setIpAddress] = useState('')
  const [cloudMode, setCloudMode] = useState<CloudMode>('Azure')
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
        <button id="theme-switcher" type="button" onClick={onToggleTheme}>
          <span id="theme-icon">{theme === 'dark' ? '☀️' : '🌙'}</span> Toggle Theme
        </button>
        {isAuthenticated && user && (
          <div id="user-info" className="user-info">
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
          <h1>IPv4 Subnet Calculator</h1>
          <p id="stack-description">{APP_CONFIG.stackName}</p>
        </header>

        {/* API Status */}
        {apiHealth && (
          <div id="api-status" className="alert alert-success">
            <strong>API Status:</strong> healthy | <strong>Backend:</strong> {apiHealth.service} |{' '}
            <strong>Version:</strong> {apiHealth.version}
            <br />
            <small>
              Frontend: <code>{window.location.origin}/</code> | Backend: <code>{apiClient.getBaseUrl()}</code>
            </small>
          </div>
        )}
        {apiError && (
          <div id="api-status" className="alert alert-error" role="alert">
            <strong>API Offline:</strong> {apiError}
          </div>
        )}

        {/* Input Form */}
        <section>
          <form id="lookup-form" onSubmit={handleSubmit}>
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
                <select id="cloud-mode" value={cloudMode} onChange={e => setCloudMode(e.target.value as CloudMode)}>
                  <option value="Standard">Standard</option>
                  <option value="AWS">AWS</option>
                  <option value="Azure">Azure</option>
                  <option value="OCI">OCI</option>
                </select>
                <button type="submit" disabled={isLoading || !ipAddress}>
                  Lookup
                </button>
              </div>
            </div>

            {/* Example Buttons */}
            <div id="example-buttons" className="example-buttons">
              <button type="button" className="secondary outline example-btn btn-rfc1918" onClick={() => handleExampleClick('10.0.0.0/24')}>
                RFC1918: 10.0.0.0/24
              </button>
              <button type="button" className="outline example-btn btn-rfc6598" onClick={() => handleExampleClick('100.64.0.1')}>
                RFC6598: 100.64.0.1
              </button>
              <button type="button" className="contrast outline example-btn btn-public" onClick={() => handleExampleClick('8.8.8.8')}>
                Public: 8.8.8.8
              </button>
              <button type="button" className="secondary example-btn btn-cloudflare" onClick={() => handleExampleClick('104.16.1.1')}>
                Cloudflare: 104.16.1.1
              </button>
            </div>
          </form>
        </section>

        {/* Loading */}
        {isLoading && (
          <div id="loading" style={{ display: 'block', textAlign: 'center', margin: '2rem 0' }} role="status">
            <div aria-busy="true"></div>
          </div>
        )}

        {/* Error */}
        {error && (
          <div id="error" className="alert alert-error" role="alert">
            <strong>Error:</strong> {error}
          </div>
        )}

        {/* Results */}
        {results && (
          <section id="results" style={{ display: 'block' }}>
            <h2>Results</h2>
            <div id="results-content">
              {/* Validation */}
              {results.results.validate && (
              <article>
                <h3>Validation</h3>
                <table>
                  <tbody>
                    <tr>
                      <td>
                        <strong>Valid</strong>
                      </td>
                      <td>{results.results.validate.valid ? 'Yes' : 'No'}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Type</strong>
                      </td>
                      <td>{results.results.validate.type}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Address</strong>
                      </td>
                      <td>{results.results.validate.address}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>IP Version</strong>
                      </td>
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
                      <td>
                        <strong>Is RFC1918</strong>
                      </td>
                      <td>{results.results.private.is_rfc1918 ? 'Yes' : 'No'}</td>
                    </tr>
                    {results.results.private.matched_rfc1918_range && (
                      <tr>
                        <td>
                          <strong>Matched Range</strong>
                        </td>
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
                      <td>
                        <strong>Is Cloudflare</strong>
                      </td>
                      <td>{results.results.cloudflare.is_cloudflare ? 'Yes' : 'No'}</td>
                    </tr>
                    {results.results.cloudflare.matched_ranges &&
                      results.results.cloudflare.matched_ranges.length > 0 && (
                        <tr>
                          <td>
                            <strong>Matched Ranges</strong>
                          </td>
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
                      <td>
                        <strong>Network</strong>
                      </td>
                      <td>{results.results.subnet.network}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Network Address</strong>
                      </td>
                      <td>{results.results.subnet.network_address}</td>
                    </tr>
                    {results.results.subnet.broadcast_address && (
                      <tr>
                        <td>
                          <strong>Broadcast Address</strong>
                        </td>
                        <td>{results.results.subnet.broadcast_address}</td>
                      </tr>
                    )}
                    <tr>
                      <td>
                        <strong>Netmask</strong>
                      </td>
                      <td>{results.results.subnet.netmask}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Prefix Length</strong>
                      </td>
                      <td>/{results.results.subnet.prefix_length}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Total Addresses</strong>
                      </td>
                      <td>{results.results.subnet.total_addresses.toLocaleString()}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Usable Addresses</strong>
                      </td>
                      <td>{results.results.subnet.usable_addresses.toLocaleString()}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>First Usable IP</strong>
                      </td>
                      <td>{results.results.subnet.first_usable_ip}</td>
                    </tr>
                    <tr>
                      <td>
                        <strong>Last Usable IP</strong>
                      </td>
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
                    <td>
                      <strong>Total Response Time</strong>
                    </td>
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
                        <td>
                          <strong>{call.duration}ms</strong>
                        </td>
                        <td>{new Date(call.requestTime).toLocaleString()}</td>
                        <td>{new Date(call.responseTime).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </details>
            </article>
            </div>
          </section>
        )}
      </main>
    </>
  )
}
