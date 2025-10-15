import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright Configuration for SWA CLI Testing
 *
 * Tests against Azure Static Web Apps CLI emulator
 * - Stack 4: http://localhost:4280 (Container App, no auth)
 * - Stack 5: http://localhost:4281 (Azure Function, JWT auth)
 *
 * Prerequisites:
 *   cd ..
 *   npm run swa -- start stack4   # or stack5
 *
 * Usage:
 *   npm run test:swa:stack4        # Test Stack 4 (no auth)
 *   npm run test:swa:stack5        # Test Stack 5 (JWT auth)
 */
export default defineConfig({
  testDir: './tests',
  testMatch: '**/swa.spec.ts',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: 1,
  reporter: 'html',
  timeout: 30000,

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:4280',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Expect SWA CLI to already be running
  // User must start: npm run swa -- start stack4
});
