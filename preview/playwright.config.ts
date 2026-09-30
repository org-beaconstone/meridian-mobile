import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: 'tests',
  workers: 1,
  use: {
    baseURL: process.env.TEST_BASE_URL || 'http://127.0.0.1:5176',
    viewport: { width: 390, height: 844 },
    launchOptions: process.env.CHROME_PATH
      ? {
          executablePath: process.env.CHROME_PATH,
          args: ['--no-sandbox', '--disable-dev-shm-usage'],
        }
      : undefined,
  },
  reporter: 'list',
});
