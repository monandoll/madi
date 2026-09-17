/**
 * 밖에서 접속 브라우저 e2e: 설정에서 켜기 한 번 → QR·주소·잠금 숫자가 나온다 (가짜 cloudflared).
 * 폰이 밖에서 들어온 상황은 터널이 붙이는 헤더로 흉내 낸다 — 숫자 화면이 먼저 뜨고, 맞히면 갤러리가 열린다.
 */
import { expect, test } from '@playwright/test';

test.describe.configure({ mode: 'serial', retries: 0 });

/** 터널을 지나온 척 (cloudflared 가 늘 붙이는 헤더) */
const REMOTE_HEADERS = { 'cf-connecting-ip': '203.0.113.9', 'cf-ray': '8a0f-ICN' };

test('설정에서 켜기 한 번이면 QR 과 잠금 숫자가 나온다', async ({ page }) => {
  await page.request.patch('/api/settings', { data: { setupDone: true } });
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/#/settings');
  const section = page.getByTestId('remote-section');
  await expect(section).toContainText('밖에서 접속하기');
  await expect(section.getByTestId('remote-status')).toHaveText('연결 안 함');

  await section.getByTestId('remote-start').click();
  const qr = section.getByTestId('remote-qr');
  await expect(qr).toBeVisible();
  await expect(section.getByTestId('remote-url')).toHaveText('https://madi-e2e.trycloudflare.com', { timeout: 30_000 });
  await expect(qr.getByTestId('qr').locator('img')).toBeVisible();
  await expect(section.getByTestId('remote-pin')).toHaveText(/잠금 숫자 \d{6}/);
  await expect(section.getByTestId('remote-status')).toHaveText('연결됨', { timeout: 30_000 });
  await expect(qr).toContainText('들어온 기기 없음');
  await expect(qr).toContainText('마디를 껐다 켜면 주소가 바뀌어요');

  // 토큰은 "고급" 안에 접혀 있다 (보통은 볼 일이 없다)
  await expect(section.getByTestId('remote-token')).toHaveCount(0);
  await section.getByTestId('remote-advanced-toggle').click();
  await expect(section.getByTestId('remote-token')).toBeVisible();
  await section.getByTestId('remote-advanced-toggle').click();

  // 전문 용어 금지 (고급을 접은 화면 기준)
  for (const banned of ['터널', '프록시', '포트', 'cloudflared']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
  await page.screenshot({ path: 'test-results/remote-settings.png', fullPage: true });
});

test('갤러리의 "폰에서 올리기" 안내에도 같은 QR 이 뜬다', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await page.getByTestId('upload-help-toggle').click();
  const help = page.getByTestId('upload-help');
  await expect(help.getByTestId('qr').locator('img')).toBeVisible({ timeout: 30_000 });
  await expect(help.getByTestId('upload-remote')).toContainText('어디서든 올릴 수 있어요');
  await expect(help.getByTestId('upload-pin')).toHaveText(/잠금 숫자 \d{6}/);
  await help.getByRole('button', { name: '닫기' }).click();
});

test('밖에서 들어온 폰은 숫자를 넣어야 갤러리가 열린다', async ({ browser, page }) => {
  // PC 화면에 보이는 숫자를 읽어 둔다
  await page.goto('/#/settings');
  const shown = await page.getByTestId('remote-pin').textContent();
  const code = /(\d{6})/.exec(shown ?? '')![1]!;

  const phone = await browser.newContext({ extraHTTPHeaders: REMOTE_HEADERS, viewport: { width: 375, height: 812 } });
  const p = await phone.newPage();
  await p.goto('/');
  await expect(p.getByTestId('pair-screen')).toBeVisible();
  await expect(p.getByTestId('pair-screen')).toContainText('6자리 숫자');

  // 틀리면 다시 묻는다
  await p.getByTestId('pair-input').fill('000000' === code ? '111111' : '000000');
  await p.getByTestId('pair-submit').click();
  await expect(p.getByTestId('pair-error')).toBeVisible();
  await p.screenshot({ path: 'test-results/remote-pair-375.png', fullPage: true });

  // 맞히면 갤러리가 열리고, 새로 고쳐도 다시 묻지 않는다
  await p.getByTestId('pair-input').fill(code);
  await p.getByTestId('pair-submit').click();
  await expect(p.getByTestId('pair-screen')).toHaveCount(0);
  await expect(p.getByTestId('upload-button')).toBeVisible({ timeout: 30_000 });
  await p.reload();
  await expect(p.getByTestId('pair-screen')).toHaveCount(0);
  await expect(p.getByTestId('upload-button')).toBeVisible({ timeout: 30_000 });

  // PC 화면은 들어온 기기를 센다
  await page.reload();
  await expect(page.getByTestId('remote-qr')).toContainText('기기 1대 들어와 있음', { timeout: 30_000 });
  await phone.close();
});

test('QR 로 들어오면 숫자를 묻지 않는다', async ({ browser, page }) => {
  await page.goto('/#/settings');
  const code = /(\d{6})/.exec((await page.getByTestId('remote-pin').textContent()) ?? '')![1]!;
  const phone = await browser.newContext({ extraHTTPHeaders: REMOTE_HEADERS, viewport: { width: 375, height: 812 } });
  const p = await phone.newPage();
  await p.goto(`/?pin=${code}`);
  await expect(p.getByTestId('upload-button')).toBeVisible({ timeout: 30_000 });
  await expect(p.getByTestId('pair-screen')).toHaveCount(0);
  // 주소에서 숫자는 지워진다 (기록에 남지 않게)
  expect(p.url()).not.toContain('pin=');
  await phone.close();
});

test('끄면 주소가 사라지고 들어와 있던 폰도 끊긴다', async ({ browser, page }) => {
  await page.goto('/#/settings');
  const section = page.getByTestId('remote-section');
  await section.getByTestId('remote-stop').click();
  await expect(section.getByTestId('remote-qr')).toHaveCount(0);
  await expect(section.getByTestId('remote-status')).toHaveText('연결 안 함');

  const phone = await browser.newContext({ extraHTTPHeaders: REMOTE_HEADERS, viewport: { width: 375, height: 812 } });
  const p = await phone.newPage();
  await p.goto('/');
  await expect(p.getByTestId('pair-screen')).toBeVisible();
  await p.getByTestId('pair-input').fill('123456');
  await p.getByTestId('pair-submit').click();
  await expect(p.getByTestId('pair-error')).toContainText('밖에서 접속을 받지 않아요');
  await phone.close();
});
