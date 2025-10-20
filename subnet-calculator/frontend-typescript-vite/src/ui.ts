/**
 * UI utilities and rendering
 */

import type { ClientPrincipal } from './entraid-auth'
import type { ApiResults } from './types'

export function showElement(id: string): void {
  const element = document.getElementById(id)
  if (element) element.style.display = 'block'
}

export function hideElement(id: string): void {
  const element = document.getElementById(id)
  if (element) element.style.display = 'none'
}

export function showLoading(): void {
  showElement('loading')
  hideElement('results')
  hideElement('error')
}

export function hideLoading(): void {
  hideElement('loading')
}

export function showError(message: string): void {
  const errorDiv = document.getElementById('error')
  if (errorDiv) {
    errorDiv.textContent = message
    showElement('error')
  }
  hideElement('results')
  hideLoading()
}

export function showApiStatus(healthy: boolean, service?: string, version?: string, endpoint?: string): void {
  const statusDiv = document.getElementById('api-status')
  if (!statusDiv) return

  if (healthy && service && version) {
    // Show backend URL, or indicate it's proxied via SWA CLI if empty
    const backendUrl = endpoint && endpoint !== '' ? endpoint : `${window.location.origin}/api`

    statusDiv.className = 'alert alert-success'
    statusDiv.innerHTML = `
      <strong>API Status:</strong> healthy |
      <strong>Backend:</strong> ${service} |
      <strong>Version:</strong> ${version}<br>
      <small>Frontend: <code>${window.location.origin}/</code> | Backend: <code>${backendUrl}</code></small>
    `
  } else {
    statusDiv.className = 'alert alert-error'
    statusDiv.innerHTML = `
      <strong>API Unavailable:</strong> Unable to connect to backend<br>
      <small>The calculator may not function correctly</small>
    `
  }
  showElement('api-status')
}

export function renderResults(results: ApiResults): void {
  const resultsContent = document.getElementById('results-content')
  if (!resultsContent) return

  let html = ''

  // Validation
  if (results.validate) {
    html += `
      <article>
        <h3>Validation</h3>
        <table>
          <tr><th>Valid</th><td>${results.validate.valid ? '✓ Yes' : '✗ No'}</td></tr>
          <tr><th>Type</th><td>${results.validate.type}</td></tr>
          <tr><th>Address</th><td><code>${results.validate.address}</code></td></tr>
          <tr><th>IP Version</th><td>${results.validate.is_ipv4 ? 'IPv4' : 'IPv6'}</td></tr>
        </table>
      </article>
    `
  }

  // Private check
  if (results.private) {
    html += `
      <article>
        <h3>Private Address Check</h3>
        <table>
          <tr><th>RFC1918 (Private)</th><td>${results.private.is_rfc1918 ? '✓ Yes' : '✗ No'}</td></tr>
          ${results.private.matched_rfc1918_range ? `<tr><th>Matched Range</th><td><code>${results.private.matched_rfc1918_range}</code></td></tr>` : ''}
          <tr><th>RFC6598 (Shared)</th><td>${results.private.is_rfc6598 ? '✓ Yes' : '✗ No'}</td></tr>
          ${results.private.matched_rfc6598_range ? `<tr><th>Matched Range</th><td><code>${results.private.matched_rfc6598_range}</code></td></tr>` : ''}
        </table>
      </article>
    `
  }

  // Cloudflare check
  if (results.cloudflare) {
    html += `
      <article>
        <h3>Cloudflare Check</h3>
        <table>
          <tr><th>Is Cloudflare</th><td>${results.cloudflare.is_cloudflare ? '✓ Yes' : '✗ No'}</td></tr>
          <tr><th>IP Version</th><td>IPv${results.cloudflare.ip_version}</td></tr>
          ${results.cloudflare.matched_ranges ? `<tr><th>Matched Ranges</th><td><code>${results.cloudflare.matched_ranges.join(', ')}</code></td></tr>` : ''}
        </table>
      </article>
    `
  }

  // Subnet info
  if (results.subnet) {
    const s = results.subnet
    html += `
      <article>
        <h3>Subnet Information (${s.mode} Mode)</h3>
        <table>
          <tr><th>Network</th><td><code>${s.network}</code></td></tr>
          <tr><th>Network Address</th><td><code>${s.network_address}</code></td></tr>
          ${s.broadcast_address ? `<tr><th>Broadcast Address</th><td><code>${s.broadcast_address}</code></td></tr>` : ''}
          <tr><th>Netmask</th><td><code>${s.netmask}</code></td></tr>
          <tr><th>Wildcard Mask</th><td><code>${s.wildcard_mask}</code></td></tr>
          <tr><th>Prefix Length</th><td>/${s.prefix_length}</td></tr>
          <tr><th>Total Addresses</th><td>${s.total_addresses.toLocaleString()}</td></tr>
          <tr><th>Usable Addresses</th><td>${s.usable_addresses.toLocaleString()}</td></tr>
          <tr><th>First Usable IP</th><td><code>${s.first_usable_ip}</code></td></tr>
          <tr><th>Last Usable IP</th><td><code>${s.last_usable_ip}</code></td></tr>
          ${s.note ? `<tr><th>Note</th><td>${s.note}</td></tr>` : ''}
        </table>
      </article>
    `
  }

  resultsContent.innerHTML = html
  showElement('results')
  hideLoading()
  hideElement('error')
}

/**
 * Show user authentication status
 */
export function showUserInfo(user: ClientPrincipal | null, authMethod: 'none' | 'jwt' | 'entraid'): void {
  const userInfoDiv = document.getElementById('user-info')
  if (!userInfoDiv) return

  if (authMethod === 'none') {
    // No authentication configured
    hideElement('user-info')
    return
  }

  if (authMethod === 'jwt') {
    // JWT auth doesn't have user info in the frontend (handled by API)
    hideElement('user-info')
    return
  }

  if (authMethod === 'entraid' && user) {
    // Show Entra ID user info
    const displayName = user.userDetails || user.userId
    userInfoDiv.innerHTML = `
      <div class="user-display">
        <span class="user-icon">👤</span>
        <span class="user-name">${displayName}</span>
        <button id="logout-btn" class="logout-btn">Logout</button>
      </div>
    `
    showElement('user-info')

    // Attach logout handler
    const logoutBtn = document.getElementById('logout-btn')
    if (logoutBtn) {
      logoutBtn.addEventListener('click', () => {
        // Azure SWA logout - redirect route defined in staticwebapp.config.json
        window.location.href = '/logout'
      })
    }
  } else if (authMethod === 'entraid') {
    // Entra ID configured but user not logged in (shouldn't happen with required auth)
    userInfoDiv.innerHTML = `
      <div class="user-display">
        <button id="login-btn" class="login-btn">Login with Entra ID</button>
      </div>
    `
    showElement('user-info')

    // Attach login handler
    const loginBtn = document.getElementById('login-btn')
    if (loginBtn) {
      loginBtn.addEventListener('click', () => {
        window.location.href = '/.auth/login/aad'
      })
    }
  }
}
