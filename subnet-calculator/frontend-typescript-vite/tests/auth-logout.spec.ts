import { expect, test } from '@playwright/test'

/**
 * Azure Static Web Apps - Entra ID Logout Tests
 *
 * Tests the logout functionality for Azure SWA with Entra ID authentication.
 * These tests verify that the logout flow works correctly and users land on
 * the logged-out page without being immediately forced to re-authenticate.
 *
 * Prerequisites:
 *   - Deploy to Azure SWA with Entra ID enabled
 *   - Set BASE_URL environment variable to the deployed SWA URL
 *   - User must be authenticated before running logout tests
 *
 * Run with:
 *   BASE_URL=https://your-app.azurestaticapps.net npm run test:auth
 */

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000'

test.describe('Entra ID Logout Flow', () => {
  test.describe.configure({ mode: 'serial' })

  test('01 - logged-out page is accessible without authentication', async ({ page }) => {
    // Navigate directly to logged-out page
    const response = await page.goto(`${BASE_URL}/logged-out.html`)

    // Should return 200 OK (not redirect to login)
    expect(response?.status()).toBe(200)

    // Should show logged-out message
    await expect(page.locator('h1')).toContainText("You've been logged out")

    // Should have "Log in again" button
    const loginButton = page.locator('a[href="/.auth/login/aad"]')
    await expect(loginButton).toBeVisible()
    await expect(loginButton).toContainText('Log in again')
  })

  test('02 - logged-out page does not expose application data', async ({ page }) => {
    await page.goto(`${BASE_URL}/logged-out.html`)

    // Should NOT have subnet calculator elements
    await expect(page.locator('#ip-address')).not.toBeVisible()
    await expect(page.locator('#lookup-form')).not.toBeVisible()
    await expect(page.locator('#results')).not.toBeVisible()

    // Should NOT have API status
    await expect(page.locator('#api-status')).not.toBeVisible()

    // Should NOT have user info (beyond the logout message)
    await expect(page.locator('#user-info')).not.toBeVisible()
  })

  test('03 - logout route redirects correctly', async ({ page }) => {
    // Navigate to /logout
    await page.goto(`${BASE_URL}/logout`, { waitUntil: 'networkidle' })

    // If authenticated: should redirect to logged-out page
    // If not authenticated: might redirect to login
    // Either way, should not stay on /logout
    expect(page.url()).not.toContain('/logout')

    // If we ended up on logged-out page, verify content
    if (page.url().includes('/logged-out.html')) {
      await expect(page.locator('h1')).toContainText("You've been logged out")
    }
  })

  test('04 - staticwebapp.config.json has correct logout configuration', async ({ request }) => {
    // Fetch the config file
    const response = await request.get(`${BASE_URL}/staticwebapp.config.json`)
    expect(response.status()).toBe(200)

    const config = await response.json()

    // Should have logged-out.html route with anonymous access
    const loggedOutRoute = config.routes.find((r: any) => r.route === '/logged-out.html')
    expect(loggedOutRoute).toBeDefined()
    expect(loggedOutRoute.allowedRoles).toContain('anonymous')

    // Should have /logout route with redirect
    const logoutRoute = config.routes.find((r: any) => r.route === '/logout')
    expect(logoutRoute).toBeDefined()
    expect(logoutRoute.redirect).toContain('/.auth/logout')
    expect(logoutRoute.redirect).toContain('post_logout_redirect_uri=/logged-out.html')

    // Should exclude logged-out.html from navigationFallback
    expect(config.navigationFallback.exclude).toContain('/logged-out.html')
  })

  test('05 - logout button redirects to /logout route', async ({ page }) => {
    // This test assumes user is authenticated
    // If testing against deployed SWA, user needs to be logged in first

    await page.goto(BASE_URL)

    // Wait for page to load
    await page.waitForSelector('h1', { state: 'visible' })

    // Check if user-info is visible (indicates authenticated session)
    const userInfo = page.locator('#user-info')
    const isVisible = await userInfo.isVisible().catch(() => false)

    if (!isVisible) {
      test.skip()
      return
    }

    // Find and click logout button
    const logoutButton = page.locator('#logout-btn')
    await expect(logoutButton).toBeVisible()

    // Click logout and wait for navigation
    await logoutButton.click()
    await page.waitForURL('**/logged-out.html', { timeout: 10000 })

    // Should land on logged-out page
    expect(page.url()).toContain('/logged-out.html')
    await expect(page.locator('h1')).toContainText("You've been logged out")
  })

  test('06 - logged-out page has correct styling and layout', async ({ page }) => {
    await page.goto(`${BASE_URL}/logged-out.html`)

    // Should use Pico CSS
    const picoLink = page.locator('link[href*="picocss"]')
    await expect(picoLink).toHaveCount(1)

    // Should have container class
    const container = page.locator('main.container')
    await expect(container).toBeVisible()

    // Should have logout-container class
    const logoutContainer = page.locator('.logout-container')
    await expect(logoutContainer).toBeVisible()

    // Should have logout icon
    const logoutIcon = page.locator('.logout-icon')
    await expect(logoutIcon).toBeVisible()
    await expect(logoutIcon).toContainText('👋')
  })

  test('07 - login button on logged-out page redirects to auth', async ({ page }) => {
    await page.goto(`${BASE_URL}/logged-out.html`)

    // Find login button
    const loginButton = page.locator('a[href="/.auth/login/aad"]')
    await expect(loginButton).toBeVisible()

    // Verify href
    const href = await loginButton.getAttribute('href')
    expect(href).toBe('/.auth/login/aad')

    // Note: We don't click it in tests as it would initiate actual authentication
    // which requires interactive login
  })

  test('08 - logout clears authentication state', async ({ page, context }) => {
    // Navigate to main app
    await page.goto(BASE_URL)
    await page.waitForSelector('h1', { state: 'visible' })

    // Check initial auth state via /.auth/me
    const authMeBefore = await page.request.get(`${BASE_URL}/.auth/me`)
    const authDataBefore = await authMeBefore.json()

    // If not authenticated, skip this test
    if (!authDataBefore.clientPrincipal) {
      test.skip()
      return
    }

    // Navigate to logout
    await page.goto(`${BASE_URL}/logout`, { waitUntil: 'networkidle' })
    await page.waitForURL('**/logged-out.html', { timeout: 10000 })

    // Check auth state after logout
    const authMeAfter = await page.request.get(`${BASE_URL}/.auth/me`)
    const authDataAfter = await authMeAfter.json()

    // clientPrincipal should be null after logout
    expect(authDataAfter.clientPrincipal).toBeNull()
  })
})
