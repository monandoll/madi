import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
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
      // 새 버전 표시 확인용: 9.9.9 를 받아 둔 것처럼 (설치를 누르면 표시만 사라진다)
      MADI_FAKE_UPDATE: '9.9.9',
      MADI_SUGGEST_ROOT: suggestRoot,
      // AI 연결 e2e: 진짜 claude 대신 fixtures/fake-claude.mjs (MCP 도구 호출은 진짜로 오간다)
      MADI_CLAUDE_BIN: path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'fake-claude.mjs'),
      // 링크로 배우기 e2e: 진짜 yt-dlp 대신 fixtures/fake-ytdlp.mjs (URL 로 샘플을 고른다)
      MADI_YTDLP: path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'fake-ytdlp.mjs'),
      // AI 깔기 e2e: 진짜 설치기 대신 가짜 codex 를 자리에 놓는 한 줄 (인터넷을 타지 않는다)
      MADI_INSTALL_CODEX: `mkdir -p "${path.join(home, 'aibin')}" && cp "${path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'fake-codex.mjs')}" "${path.join(home, 'aibin', 'codex')}" && chmod +x "${path.join(home, 'aibin', 'codex')}"`,
      // 설치기가 놓는 자리를 엔진 PATH 에 넣어 둔다 (진짜 설치기도 PATH 자리에 놓는다)
      PATH: `${path.join(home, 'aibin')}${path.delimiter}${process.env['PATH'] ?? ''}`,
      // 밖에서 접속 e2e: 진짜 cloudflared 대신 fixtures/fake-cloudflared.mjs (주소 한 줄을 찍고 살아 있는다)
      MADI_CLOUDFLARED: path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'fake-cloudflared.mjs'),
      MADI_FAKE_TUNNEL_HOST: 'madi-e2e',
      // 갤러리 "폴더 열기": 탐색기 대신 fixtures/fake-opener.mjs (연 경로를 MADI_HOME/opened.txt 에 적는다)
      MADI_OPENER: path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'fake-opener.mjs'),
    },
  },
});
