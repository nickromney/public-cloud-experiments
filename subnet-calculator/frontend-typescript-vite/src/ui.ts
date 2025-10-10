/**
 * UI utilities and rendering
 */

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
    statusDiv.className = 'alert alert-success'
    statusDiv.innerHTML = `
      <strong>API Status:</strong> healthy |
      <strong>Backend:</strong> ${service} |
      <strong>Version:</strong> ${version}<br>
      <small>Frontend: <code>${window.location.origin}/</code> | Backend: <code>${endpoint || 'N/A'}</code></small>
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
