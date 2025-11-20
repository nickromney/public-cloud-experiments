import { expect, test } from '@playwright/test'

const KEYCLOAK_URL_PATTERN = /realms\/subnet-calculator\/protocol\/openid-connect\/auth/i
const EXTENDED_TIMEOUT_MS = 30000

const demoUser = {
  username: process.env.STACK12_USERNAME || 'demo',
  password: process.env.STACK12_PASSWORD || 'password123',
}

test.describe('Stack 12 - OAuth2 Proxy + APIM simulator', () => {
  test('user must authenticate before accessing frontend and API calls succeed', async ({ page }, testInfo) => {
    testInfo.setTimeout(testInfo.timeout + EXTENDED_TIMEOUT_MS)
    page.on('console', (message) => {
      // eslint-disable-next-line no-console
      console.log('[browser]', message.text())
    })
    await page.goto('/')

    // OAuth2 Proxy shows a sign-in interstitial before redirecting to Keycloak
    const signInButton = page.getByRole('button', { name: /sign in/i }).first()
    await expect(signInButton).toBeVisible({ timeout: 15000 })
    await signInButton.click()

    await page.waitForURL(KEYCLOAK_URL_PATTERN, { timeout: 15000 })

    await page.locator('input[name="username"]').fill(demoUser.username)
    await page.locator('input[name="password"]').fill(demoUser.password)
    await page.getByRole('button', { name: /sign in|log in/i }).click()

    // Redirect back to the protected frontend via OAuth2 Proxy
    await page.waitForURL(/localhost:3007/, { timeout: 15000 })
    await expect(page.getByRole('heading', { level: 1, name: /IPv4 Subnet Calculator/i })).toBeVisible({ timeout: 15000 })

    // API health widget should surface backend state (APIM simulator -> FastAPI)
    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible({ timeout: 20000 })

    // Auto-login should complete and show logout button
    await expect(page.getByRole('button', { name: /logout/i })).toBeVisible({ timeout: 20000 })

    // Perform a full lookup that requires hitting the APIM simulator on :8082
    const ipInput = page.getByLabel(/IP Address or CIDR Range/i)
    await ipInput.fill('8.8.8.8')

    await page.getByRole('button', { name: /lookup|calculate/i }).click()

    await expect(page.getByText(/8\.8\.8\.8/)).toBeVisible({ timeout: 15000 })
    await expect(page.getByText(/RFC1918/i)).toBeVisible()
  })
})
