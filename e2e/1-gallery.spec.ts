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

test.describe.configure({ mode: 'serial', retries: 0 });

test('처음 켜면 설정 카드가 뜨고, 이름과 폴더를 고르면 영상이 나타난다', async ({ page }) => {
  await patchSettings(page, { workspaceName: '내 스튜디오', watchFolders: [], setupDone: false, ai: { provider: 'none' } });
  fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(VIDEOS, '햄스트링 패시브 스트레칭 풀버전.mp4'));
  fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(VIDEOS, '거북목 교정 2편 재촬영.mp4'));

  await page.goto('/');
  await expect(page).toHaveTitle('마디');

  // 설정 전에는 첫 실행 화면만 (design/v2 Desktop 첫 실행 카드)
  const card = page.getByTestId('setup-card');
  await expect(card).toBeVisible();
  await expect(card.getByText('두 가지만 정하면 시작합니다')).toBeVisible();
  await expect(card.getByTestId('setup-name')).toHaveValue('내 스튜디오');
  await expect(page.getByTestId('video-card')).toHaveCount(0);

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
  await expect(page.getByText('AI 연결 안 됨')).toBeVisible();
  await expect(page.getByTestId('engine-dot')).toHaveCSS('background-color', 'rgb(122, 158, 126)');
  for (const banned of ['인코딩', '프록시', '트랜스크립트']) {
    await expect(page.getByText(banned)).toHaveCount(0);
  }
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
  await expect(list.getByText('동영상', { exact: true })).toBeVisible(); // 폴더 이름이 아니라 한국어 라벨
  await page.getByTestId('folder-list').getByRole('button', { name: '폴더 추가…' }).click();
  const chooser = page.getByTestId('folder-chooser');
  await expect(chooser.getByRole('checkbox', { name: /동영상/ })).toHaveCount(0); // 이미 고른 건 안 보임
  await chooser.getByRole('checkbox', { name: /바탕화면/ }).click();
  await expect(list.getByText(DESKTOP)).toBeVisible();
  await expect.poll(async () => (await (await page.request.get('/api/settings')).json()).settings.watchFolders).toEqual([VIDEOS, DESKTOP]);

  // 시스템 선택창은 브라우저만 뜬 상태에선 안내 문구
  await page.getByTestId('folder-list').getByRole('button', { name: '폴더 추가…' }).click();
  await page.getByTestId('folder-chooser').getByRole('button', { name: '폴더 추가…' }).click();
  await expect(page.getByText('폴더 선택창은')).toBeVisible();

  // 폴더 빼기
  await list.locator('div', { hasText: DESKTOP }).getByRole('button', { name: '빼기' }).first().click();
  await expect(list.getByText(DESKTOP)).toHaveCount(0);

  // AI 는 조용히
  await expect(screen.getByText('연결 안 됨')).toBeVisible();

  // 밖에서 접속: 고정 주소(토큰)는 '고급' 안에 접혀 있다. 넣으면 저장되고, 끊으면 원래대로.
  const remote = screen.getByTestId('remote-section');
  await expect(remote.getByTestId('remote-status')).toHaveText('연결 안 함');
  await expect(remote.getByTestId('remote-token')).toHaveCount(0);
  await remote.getByTestId('remote-advanced-toggle').click();
  await remote.getByTestId('remote-token').fill('eyJhIjoiZmFrZSJ9');
  await remote.getByRole('button', { name: '연결' }).click();
  await expect(remote.getByTestId('remote-status')).not.toHaveText('연결 안 함');
  await expect.poll(async () => (await (await page.request.get('/api/settings')).json()).settings.tunnelToken).toBe('eyJhIjoiZmFrZSJ9');
  await remote.getByRole('button', { name: '끊기' }).click();
  await expect(remote.getByTestId('remote-status')).toHaveText('연결 안 함');
  await expect.poll(async () => (await (await page.request.get('/api/settings')).json()).settings.remoteMode).toBe('off');
  await expect(screen.getByText(/^마디 \d+\.\d+\.\d+$/)).toBeVisible();

  // 사이드바 '영상' → 갤러리, 사이드바 맨 위에 새 이름
  await page.getByRole('tab', { name: '영상' }).click();
  await expect(page).toHaveURL(/#\/$/);
  await expect(page.getByRole('heading', { name: '움직임 연구소' })).toBeVisible();
  await expect(page.getByTestId('video-card')).toHaveCount(2);
});

test('탭: 진행 중 · 결과물', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: '진행 중' }).click();
  await expect(page.getByTestId('empty')).toContainText('진행 중인 작업이 없습니다');
  await page.getByRole('tab', { name: '결과물' }).click();
  await expect(page.getByTestId('empty')).toContainText('결과물이 없습니다');
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

test('PC 의 "폴더 열기"는 이 PC 의 영상 폴더를 연다 (설정으로 가지 않는다)', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const opened = path.join(process.env['MADI_E2E_HOME']!, 'opened.txt');
  fs.rmSync(opened, { force: true });
  await page.getByTestId('open-folder').click();
  await expect.poll(() => (fs.existsSync(opened) ? fs.readFileSync(opened, 'utf8') : null), { timeout: 10_000 }).toBe(VIDEOS);
  // 설정으로 가지 않고 갤러리에 그대로
  await expect(page).not.toHaveURL(/settings/);
  await expect(page.getByTestId('video-card')).toHaveCount(2);
});

test('폰(375)에서 "올리기"로 영상을 올리면 진행 줄이 뜨고 갤러리에 카드가 생긴다', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');
  await expect(page.getByTestId('video-card')).toHaveCount(2);
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), page.getByTestId('upload-button').click()]);
  await chooser.setFiles({ name: '폰 촬영 어깨 루틴.mp4', mimeType: 'video/mp4', buffer: fs.readFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4')) });
  const row = page.getByTestId('upload-row');
  await expect(row).toHaveCount(1);
  await expect(row).toContainText('폰 촬영 어깨 루틴.mp4');
  // 다 올라가면 갤러리에 나타나고 진행 줄은 사라진다
  await expect(page.getByTestId('video-card')).toHaveCount(3, { timeout: 30_000 });
  await expect(page.locator('[data-testid="video-card"]', { hasText: '폰 촬영 어깨 루틴' })).toBeVisible();
  await expect(row).toHaveCount(0, { timeout: 10_000 });
  expect(fs.existsSync(path.join(VIDEOS, '폰 촬영 어깨 루틴.mp4'))).toBe(true);
  for (const banned of ['tus', '업로드 중', 'upload']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
  // 영상이 아닌 파일은 올리지 않고 이유를 말한다
  const [chooser2] = await Promise.all([page.waitForEvent('filechooser'), page.getByTestId('upload-button').click()]);
  await chooser2.setFiles({ name: '메모.txt', mimeType: 'text/plain', buffer: Buffer.from('x') });
  await expect(page.getByTestId('upload-status')).toHaveText('영상 파일만 올릴 수 있습니다.');
  await page.getByTestId('upload-remove').click();
  await expect(page.getByTestId('upload-row')).toHaveCount(0);
  // 뒷정리: 올린 파일을 지우면 갤러리에서도 빠진다 (다음 스펙은 카드 2개를 기대한다)
  fs.rmSync(path.join(VIDEOS, '폰 촬영 어깨 루틴.mp4'));
  await expect(page.getByTestId('video-card')).toHaveCount(2, { timeout: 30_000 });
});

test('PC 의 "폰에서 업로드"는 안내 카드를 열고, 거기서 이 브라우저 파일도 올릴 수 있다', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await page.getByTestId('upload-help-toggle').click();
  const help = page.getByTestId('upload-help');
  await expect(help).toBeVisible();
  await expect(help).toContainText('폰에서 마디를 열면');
  await expect(help.getByTestId('upload-remote')).toContainText('밖에서 접속하기');
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), help.getByTestId('upload-pick-here').click()]);
  await chooser.setFiles({ name: '데스크 업로드.mp4', mimeType: 'video/mp4', buffer: fs.readFileSync(path.join(FIXTURES, 'sample-5s.mp4')) });
  await expect(page.locator('[data-testid="video-card"]', { hasText: '데스크 업로드' })).toBeVisible({ timeout: 30_000 });
  await help.getByRole('button', { name: '닫기' }).click();
  await expect(help).toHaveCount(0);
  fs.rmSync(path.join(VIDEOS, '데스크 업로드.mp4'));
  await expect(page.getByTestId('video-card')).toHaveCount(2, { timeout: 30_000 });
});
