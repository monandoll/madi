import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test, type Page } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'fixtures');
const HOME = process.env['MADI_E2E_HOME']!;
const SUGGEST = path.join(HOME, 'suggest');
const VIDEOS = path.join(SUGGEST, 'Videos');
const DESKTOP = path.join(SUGGEST, 'Desktop');

async function patchSettings(page: Page, body: Record<string, unknown>) {
  const res = await page.request.patch('/api/settings', { data: body });
  expect(res.ok()).toBeTruthy();
}

test.describe.configure({ mode: 'serial' });

test('처음 켜면 설정 카드가 뜨고, 이름과 폴더를 고르면 영상이 나타난다', async ({ page }) => {
  await patchSettings(page, { workspaceName: '내 스튜디오', watchFolders: [], setupDone: false });
  fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(VIDEOS, '햄스트링 패시브 스트레칭 풀버전.mp4'));
  fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(VIDEOS, '거북목 교정 2편 재촬영.mp4'));

  await page.goto('/');
  await expect(page).toHaveTitle('마디');
  await expect(page.getByRole('heading', { name: '내 스튜디오' })).toBeVisible();
  await expect(page.getByText('AI 연결 안 됨')).toBeVisible();
  await expect(page.getByTestId('engine-dot')).toHaveCSS('background-color', 'rgb(122, 158, 126)');
  for (const banned of ['인코딩', '프록시', '트랜스크립트']) {
    await expect(page.getByText(banned)).toHaveCount(0);
  }

  const card = page.getByTestId('setup-card');
  await expect(card).toBeVisible();
  await expect(card.getByText('처음이시죠?')).toBeVisible();
  await expect(page.getByTestId('empty')).toContainText('폴더를 고르면');

  // 엔진이 찾아 준 후보: 동영상(영상 2개), 바탕화면(영상 없음)
  const videosRow = card.getByRole('radio', { name: /동영상/ });
  await expect(videosRow).toContainText('영상 2개');
  await expect(card.getByRole('radio', { name: /바탕화면/ })).toContainText('영상 없음');

  await card.getByTestId('setup-name').fill('재활운동 연구소');
  await videosRow.click();
  await expect(videosRow).toHaveAttribute('aria-checked', 'true');
  await card.getByTestId('setup-start').click();

  await expect(card).toHaveCount(0);
  await expect(page.getByRole('heading', { name: '재활운동 연구소' })).toBeVisible();
  const cards = page.getByTestId('video-card');
  await expect(cards).toHaveCount(2, { timeout: 30_000 });
  await expect(page.locator('[data-testid="video-card"][data-status="ready"]')).toHaveCount(2, { timeout: 60_000 });
  await expect(page.getByText('준비 중')).toHaveCount(0);

  const first = cards.first();
  await expect(first.getByText(/^\d+:\d{2}$/)).toBeVisible();
  const img = first.locator('img');
  await expect(img).toBeVisible();
  await expect.poll(async () => img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);

  // 새로고침해도 카드는 다시 안 뜬다
  await page.reload();
  await expect(page.getByTestId('video-card')).toHaveCount(2);
  await expect(page.getByTestId('setup-card')).toHaveCount(0);
});

test('설정 화면: 톱니로 들어가서 이름을 바꾸고 폴더를 더하고 뺀다', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '설정' }).click();
  await expect(page).toHaveURL(/#\/settings$/);
  const screen = page.getByTestId('settings-screen');
  await expect(screen).toBeVisible();

  // 이름
  const name = page.getByTestId('settings-name');
  await expect(name).toHaveValue('재활운동 연구소');
  await name.fill('  움직임 연구소  ');
  await name.press('Enter');
  await expect.poll(async () => (await (await page.request.get('/api/settings')).json()).settings.workspaceName).toBe('움직임 연구소');
  await name.fill('   ');
  await name.press('Enter');
  await expect(name).toHaveValue('움직임 연구소');

  // 폴더 더하기: 바탕화면
  const list = page.getByTestId('folder-list');
  await expect(list.getByText(VIDEOS)).toBeVisible();
  await page.getByRole('button', { name: '폴더 추가…' }).click();
  const chooser = page.getByTestId('folder-chooser');
  await expect(chooser.getByRole('checkbox', { name: /동영상/ })).toHaveCount(0); // 이미 고른 건 안 보임
  await chooser.getByRole('checkbox', { name: /바탕화면/ }).click();
  await expect(list.getByText(DESKTOP)).toBeVisible();
  await expect.poll(async () => (await (await page.request.get('/api/settings')).json()).settings.watchFolders).toEqual([VIDEOS, DESKTOP]);

  // 시스템 선택창은 브라우저만 뜬 상태에선 안내 문구
  await page.getByRole('button', { name: '폴더 추가…' }).click();
  await page.getByTestId('folder-chooser').getByRole('button', { name: '폴더 추가…' }).click();
  await expect(page.getByText('폴더 선택창은')).toBeVisible();

  // 폴더 빼기
  await list.locator('div', { hasText: DESKTOP }).getByRole('button', { name: '빼기' }).first().click();
  await expect(list.getByText(DESKTOP)).toHaveCount(0);

  // AI 는 조용히
  await expect(screen.getByText('연결 안 됨')).toBeVisible();
  await expect(screen.getByText(/^마디 \d+\.\d+\.\d+$/)).toBeVisible();

  // 뒤로 → 갤러리 헤더에 새 이름
  await page.getByRole('button', { name: '뒤로' }).click();
  await expect(page.getByRole('heading', { name: '움직임 연구소' })).toBeVisible();
  await expect(page.getByTestId('video-card')).toHaveCount(2);
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
