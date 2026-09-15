import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test, type Page } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'fixtures');
const HOME = process.env['MADI_E2E_HOME']!;
const WATCH = path.join(HOME, 'videos');

async function patchSettings(page: Page, body: Record<string, unknown>) {
  const res = await page.request.patch('/api/settings', { data: body });
  expect(res.ok()).toBeTruthy();
}

test.describe.configure({ mode: 'serial' });

test('폴더가 없으면 안내 문구, 헤더엔 워크스페이스명과 AI 미연결', async ({ page }) => {
  await patchSettings(page, { workspaceName: '수현쌤 스튜디오', watchFolders: [] });
  await page.goto('/');
  await expect(page).toHaveTitle('마디');
  await expect(page.getByRole('heading', { name: '수현쌤 스튜디오' })).toBeVisible();
  await expect(page.getByText('AI 연결 안 됨')).toBeVisible();
  await expect(page.getByTestId('empty')).toContainText('영상 폴더가 없어요');
  // 상태 점은 엔진 연결(ok 색)
  await expect(page.getByTestId('engine-dot')).toHaveCSS('background-color', 'rgb(122, 158, 126)');
  // 전문 용어가 화면에 없어야 한다
  for (const banned of ['인코딩', '프록시', '트랜스크립트']) {
    await expect(page.getByText(banned)).toHaveCount(0);
  }
});

test('폴더에 영상을 넣으면 카드가 나타나고 준비가 끝나면 썸네일과 길이가 보인다', async ({ page }) => {
  fs.mkdirSync(WATCH, { recursive: true });
  await patchSettings(page, { watchFolders: [WATCH] });
  await page.goto('/');
  await expect(page.getByTestId('empty')).toContainText('영상이 아직 없어요');

  fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(WATCH, '햄스트링 패시브 스트레칭 풀버전.mp4'));
  fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(WATCH, '거북목 교정 2편 재촬영.mp4'));

  const cards = page.getByTestId('video-card');
  await expect(cards).toHaveCount(2, { timeout: 30_000 });
  await expect(cards.filter({ hasText: '햄스트링 패시브 스트레칭 풀버전' })).toBeVisible();

  // WS 이벤트로 ready 가 반영된다 (새로고침 없이)
  await expect(cards.filter({ has: page.locator('[data-status="ready"]') })).toHaveCount(0);
  await expect(page.locator('[data-testid="video-card"][data-status="ready"]')).toHaveCount(2, { timeout: 60_000 });
  await expect(page.getByText('준비 중')).toHaveCount(0);

  const first = cards.first();
  await expect(first.getByText(/^\d+:\d{2}$/)).toBeVisible();
  const img = first.locator('img');
  await expect(img).toBeVisible();
  await expect.poll(async () => img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
});

test('탭: 진행 중 · 결과물', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: '진행 중' }).click();
  await expect(page.getByTestId('empty')).toContainText('하고 있는 일이 없어요');
  await page.getByRole('tab', { name: '결과물' }).click();
  await expect(page.getByTestId('empty')).toContainText('결과물이 없어요');
  await page.getByRole('tab', { name: '영상' }).click();
  await expect(page.getByTestId('video-card')).toHaveCount(2);
});

test('375 폭에서 카드가 2열이다', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');
  const cards = page.getByTestId('video-card');
  await expect(cards).toHaveCount(2);
  const [a, b] = await Promise.all([cards.nth(0).boundingBox(), cards.nth(1).boundingBox()]);
  expect(a && b && Math.abs(a.y - b.y) < 1).toBeTruthy(); // 같은 줄
  expect(a!.width).toBeGreaterThan(150);
  expect(a!.width).toBeLessThan(190);
  await page.screenshot({ path: 'test-results/gallery-375.png', fullPage: true });
});

test('넓은 화면에서는 같은 카드 폭으로 열이 늘어난다', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const cards = page.getByTestId('video-card');
  await expect(cards).toHaveCount(2);
  const [a, b] = await Promise.all([cards.nth(0).boundingBox(), cards.nth(1).boundingBox()]);
  expect(a && b && Math.abs(a.y - b.y) < 1).toBeTruthy();
  expect(a!.width).toBeGreaterThan(168);
  expect(a!.width).toBeLessThan(260);
});
