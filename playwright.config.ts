import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { defineConfig, devices } from '@playwright/test';

/**
 * 브라우저 e2e. 엔진을 임시 홈으로 띄우고(webServer), 빌드된 웹앱을 엔진이 서빙한 화면을 검사한다.
 * 먼저 `pnpm --filter @madi/web build` 가 되어 있어야 한다.
 */
const PORT = Number(process.env['MADI_E2E_PORT'] ?? 41521);
const home = process.env['MADI_E2E_HOME'] ?? fs.mkdtempSync(path.join(os.tmpdir(), 'madi-pw-'));
process.env['MADI_E2E_HOME'] = home;
// 엔진이 "동영상/바탕화면/다운로드" 후보를 찾는 홈. 테스트용 폴더 두 개를 미리 만든다.
const suggestRoot = path.join(home, 'suggest');
for (const d of ['Videos', 'Desktop']) fs.mkdirSync(path.join(suggestRoot, d), { recursive: true });

export default defineConfig({
  testDir: './e2e',
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env['CI'] ? 1 : 0,
  reporter: process.env['CI'] ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    ...(process.env['PW_CHROMIUM_PATH'] ? { launchOptions: { executablePath: process.env['PW_CHROMIUM_PATH'] } } : {}),
  },
  // 한 엔진(한 DB)을 공유하므로 프로젝트는 하나. 폭은 테스트 안에서 바꾼다.
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'pnpm --filter @madi/engine start',
    url: `http://127.0.0.1:${PORT}/api/health`,
    reuseExistingServer: false,
    timeout: 60_000,
    env: {
      MADI_HOME: home,
      MADI_PORT: String(PORT),
      MADI_QUIET: '1',
      MADI_SUGGEST_ROOT: suggestRoot,
    },
  },
});
