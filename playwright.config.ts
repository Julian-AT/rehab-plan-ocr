import { defineConfig, devices } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  use: { baseURL: "http://127.0.0.1:1420", trace: "retain-on-failure" },
  webServer: {
    command: "npm run preview",
    url: "http://127.0.0.1:1420",
    reuseExistingServer: false,
  },
  projects: [
    {
      name: "desktop-chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 1000 },
      },
    },
    {
      name: "mobile-webkit",
      use: { ...devices["iPhone 13"], viewport: { width: 393, height: 852 } },
    },
  ],
});
