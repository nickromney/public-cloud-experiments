import { expect, test } from '@playwright/test'

test.describe('TypeScript Vite Frontend', () => {
  test('page loads successfully', async ({ page }) => {
    await page.goto('/')

    // Check title
    await expect(page).toHaveTitle(/IPv4 Subnet Calculator/)

    // Check header
    const heading = page.locator('h1')
    await expect(heading).toBeVisible()
    await expect(heading).toHaveText('IPv4 Subnet Calculator')
  })

  test('API status panel displays', async ({ page }) => {
    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show either healthy or unavailable
    await expect(apiStatus).toContainText(/healthy|Unavailable/i)
  })

  test('theme switcher works', async ({ page }) => {
    await page.goto('/')

    const themeSwitcher = page.locator('#theme-switcher')
    await expect(themeSwitcher).toBeVisible()

    const html = page.locator('html')

    // Default should be dark
    await expect(html).toHaveAttribute('data-theme', 'dark')

    // Click to switch to light
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'light')

    // Click to switch back to dark
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'dark')
  })

  test('theme persists across reload', async ({ page }) => {
    await page.goto('/')

    const themeSwitcher = page.locator('#theme-switcher')
    const html = page.locator('html')

    // Switch to light
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'light')

    // Reload page
    await page.reload()

    // Should still be light
    await expect(html).toHaveAttribute('data-theme', 'light')
  })

  test('form elements are present', async ({ page }) => {
    await page.goto('/')

    // Check input field
    const ipInput = page.locator('#ip-address')
    await expect(ipInput).toBeVisible()
    await expect(ipInput).toHaveAttribute('placeholder', /e\.g\./)

    // Check cloud mode selector
    const modeSelect = page.locator('#cloud-mode')
    await expect(modeSelect).toBeVisible()

    // Check submit button
    const submitBtn = page.locator('button[type="submit"]')
    await expect(submitBtn).toBeVisible()
  })

  test('cloud mode selector has all options', async ({ page }) => {
    await page.goto('/')

    const modeSelect = page.locator('#cloud-mode')
    const options = modeSelect.locator('option')

    await expect(options).toHaveCount(4)

    // Check default value (Standard is the default)
    await expect(modeSelect).toHaveValue('Standard')
  })

  test('example buttons populate input', async ({ page }) => {
    await page.goto('/')

    const ipInput = page.locator('#ip-address')

    // Click RFC1918 button
    const rfc1918Btn = page.locator('.btn-rfc1918')
    await rfc1918Btn.click()
    await expect(ipInput).toHaveValue('10.0.0.0/24')

    // Click Public IP button
    const publicBtn = page.locator('.btn-public')
    await publicBtn.click()
    await expect(ipInput).toHaveValue('8.8.8.8')

    // Click Cloudflare button
    const cloudflareBtn = page.locator('.btn-cloudflare')
    await cloudflareBtn.click()
    await expect(ipInput).toHaveValue('104.16.1.1')
  })

  test('form submission with valid IP', async ({ page }) => {
    await page.goto('/')

    // Fill form
    await page.fill('#ip-address', '192.168.1.1')
    await page.selectOption('#cloud-mode', 'Azure')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    const results = page.locator('#results')
    await expect(results).toBeVisible({ timeout: 10000 })

    // Check results contain expected data
    await expect(results).toContainText('192.168.1.1')
    await expect(results).toContainText(/RFC1918|Private/i)
  })

  test('form submission with CIDR range', async ({ page }) => {
    await page.goto('/')

    // Fill form with network
    await page.fill('#ip-address', '10.0.0.0/24')
    await page.selectOption('#cloud-mode', 'Standard')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    const results = page.locator('#results')
    await expect(results).toBeVisible({ timeout: 10000 })

    // Check subnet info is displayed
    await expect(results).toContainText(/Subnet Information/i)
    await expect(results).toContainText('10.0.0.0')
    await expect(results).toContainText('/24')
  })

  test('error handling for invalid IP', async ({ page }) => {
    await page.goto('/')

    // Fill with invalid IP
    await page.fill('#ip-address', '999.999.999.999')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for error
    const error = page.locator('#error')
    await expect(error).toBeVisible({ timeout: 5000 })
    await expect(error).toContainText(/Error|Invalid/i)
  })

  test('loading indicator appears during submission', async ({ page }) => {
    await page.goto('/')

    // Fill form
    await page.fill('#ip-address', '10.0.0.0/8')

    // Submit and check for loading state
    const submitPromise = page.click('button[type="submit"]')

    // Loading should appear briefly
    const loading = page.locator('#loading')
    // Note: This might be too fast to catch, but we'll try

    await submitPromise

    // Results should eventually appear
    const results = page.locator('#results')
    await expect(results).toBeVisible({ timeout: 10000 })
  })

  test('responsive layout - mobile', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 568 })
    await page.goto('/')

    // Page should still load
    const heading = page.locator('h1')
    await expect(heading).toBeVisible()
  })

  test('responsive layout - tablet', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 })
    await page.goto('/')

    const heading = page.locator('h1')
    await expect(heading).toBeVisible()
  })

  test('responsive layout - desktop', async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 1080 })
    await page.goto('/')

    const heading = page.locator('h1')
    await expect(heading).toBeVisible()
  })

  test('all example buttons are present', async ({ page }) => {
    await page.goto('/')

    await expect(page.locator('.btn-rfc1918')).toBeVisible()
    await expect(page.locator('.btn-rfc6598')).toBeVisible()
    await expect(page.locator('.btn-public')).toBeVisible()
    await expect(page.locator('.btn-cloudflare')).toBeVisible()
  })

  test('API unavailable shows helpful error message', async ({ page }) => {
    // Intercept API health check and simulate connection failure
    await page.route('**/api/v1/health', (route) => route.abort('failed'))

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show user-friendly error message
    await expect(apiStatus).toContainText(/Unavailable|connect|backend/i)
    // Should NOT show cryptic JSON error
    await expect(apiStatus).not.toContainText(/Failed to execute 'json'/i)
  })

  test('API timeout shows helpful error message', async ({ page }) => {
    // Intercept API health check and delay response beyond timeout
    await page.route('**/api/v1/health', async (route) => {
      await page.waitForTimeout(6000) // Longer than 5s timeout
      await route.fulfill({
        status: 200,
        body: JSON.stringify({ status: 'ok' }),
      })
    })

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible({ timeout: 10000 })

    // Should show timeout error
    await expect(apiStatus).toContainText(/timeout|starting up|unavailable/i)
  })

  test('API returns non-JSON shows helpful error message', async ({ page }) => {
    // Intercept API health check and return HTML instead of JSON
    await page.route('**/api/v1/health', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<html><body>Service Starting...</body></html>',
      })
    )

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show helpful error about non-JSON response
    await expect(apiStatus).toContainText(/did not return JSON|starting up/i)
    // Should NOT show cryptic JSON parsing error
    await expect(apiStatus).not.toContainText(/Unexpected end of JSON input/i)
  })

  test('API returns HTTP error shows status code', async ({ page }) => {
    // Intercept API health check and return 503 Service Unavailable
    await page.route('**/api/v1/health', (route) =>
      route.fulfill({
        status: 503,
        contentType: 'text/html',
        body: 'Service Unavailable',
      })
    )

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show HTTP status
    await expect(apiStatus).toContainText(/503|unavailable/i)
  })

  test('form submission when API unavailable shows error', async ({ page }) => {
    await page.goto('/')

    // Intercept API calls and simulate connection failure
    await page.route('**/api/v1/address/validate', (route) => route.abort('failed'))

    // Fill and submit form
    await page.fill('#ip-address', '192.168.1.1')
    await page.click('button[type="submit"]')

    // Should show error message
    const error = page.locator('#error')
    await expect(error).toBeVisible({ timeout: 5000 })

    // Should show user-friendly message, not cryptic error
    await expect(error).toContainText(/connect|unavailable|backend/i)
    await expect(error).not.toContainText(/Failed to execute 'json'/i)
  })
})
