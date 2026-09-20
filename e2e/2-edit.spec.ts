/**
 * 2단계 브라우저 e2e: 영상 상세(미연결) → 버튼 → 진행 카드 → 결과물 카드 → 결과물 화면 → 다운로드.
 * 1-gallery.spec 뒤에 돈다 (같은 엔진). 무음 구간 샘플을 Downloads 에 넣고 설정을 직접 맞춘다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'fixtures');
const HOME = process.env['MADI_E2E_HOME']!;
// gallery.spec 의 Videos 폴더는 건드리지 않는다 (개수 검증이 있음). 이 스펙은 Downloads 를 쓴다.
const VIDEOS = path.join(HOME, 'suggest', 'Downloads');

// 순차 + 상태를 쌓는 스펙이라 재시도하면 앞 테스트의 결과물이 남아 오히려 깨진다 → 재시도 없음
test.describe.configure({ mode: 'serial', retries: 0 });

test('상세: 인사말, 프리뷰 펼치기, 세로로 바꾸기 → 결과물 카드', async ({ page }) => {
  fs.mkdirSync(VIDEOS, { recursive: true });
  fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(VIDEOS, '어깨 가동성 루틴 3분.mp4'));
  await page.request.patch('/api/settings', { data: { watchFolders: [VIDEOS], setupDone: true, workspaceName: '재활운동 연구소', ai: { provider: 'none' } } });
  await page.goto('/');
  const card = page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' });
  await expect(card).toHaveAttribute('data-status', 'ready', { timeout: 60_000 });
  await card.click();

  await expect(page).toHaveURL(/#\/videos\//);
  const detail = page.getByTestId('video-detail');
  await expect(detail.getByRole('heading', { name: '어깨 가동성 루틴 3분' })).toBeVisible();
  await expect(page.getByTestId('bubble-assistant').first()).toContainText('무엇을 해드릴까요');
  await expect(page.getByText('결과물 없음').first()).toBeVisible();

  // 프리뷰 펼치기 → 플레이어
  await page.getByTestId('preview-toggle').click();
  await expect(page.getByTestId('preview-video')).toBeVisible();
  await page.getByTestId('preview-toggle').click();
  await expect(page.getByTestId('preview-video')).toHaveCount(0);

  // 전문 용어 금지
  for (const banned of ['인코딩', '프록시', '트랜스크립트', '렌더']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }

  // 버튼 4개, 입력창 없음
  const bar = page.getByTestId('action-bar');
  await expect(bar.getByRole('button')).toHaveCount(4);
  await expect(page.getByPlaceholder('말로 요청하세요')).toHaveCount(0);

  await bar.locator('[data-action="vertical"]').click();
  await expect(page.getByTestId('bubble-user')).toContainText('세로로 바꿔줘');
  await expect(page.getByTestId('progress-card')).toBeVisible();
  await expect(bar.locator('[data-action="vertical"]')).toBeDisabled(); // 돌아가는 동안은 잠김
  await expect(page.getByTestId('output-row')).toHaveCount(1, { timeout: 90_000 });
  await expect(page.getByTestId('progress-card')).toHaveCount(0);
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('세로로 바꿨습니다');
  await expect(page.getByTestId('output-row')).toContainText('9:16');
  await expect(page.getByText('결과물 1개').first()).toBeVisible();
});

test('쉬는 구간 잘라내기 → 잘라낸 결과 문구, 결과물 2개', async ({ page }) => {
  await page.goto('/');
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  await page.getByTestId('action-bar').locator('[data-action="silence"]').click();
  await expect(page.getByTestId('output-row')).toHaveCount(2, { timeout: 90_000 });
  await expect(page.getByTestId('bubble-assistant').last()).toContainText(/쉬는 구간 2곳.*잘라냈습니다/);
  // 갤러리 카드 배지
  await page.goto('/');
  await expect(page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' })).toContainText('결과물 2개');
  await page.getByRole('tab', { name: '결과물' }).click();
  await expect(page.getByTestId('output-list').getByTestId('output-row')).toHaveCount(2);
});

test('숏폼 자르기: 구간 고르고 만들기 → 결과물 화면 → 다운로드', async ({ page }) => {
  await page.goto('/');
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  await page.getByTestId('action-bar').locator('[data-action="short"]').click();
  const picker = page.getByTestId('short-picker');
  await expect(picker).toBeVisible();
  await picker.getByTestId('short-start').fill('1');
  await picker.getByTestId('short-end').fill('4');
  // 자막은 whisper 가 없을 수 있어 끈다 (체크박스는 sr-only, 라벨을 누른다)
  const subsLabel = picker.getByText('자막도 넣기');
  if (await subsLabel.count()) {
    await subsLabel.click();
    await expect(picker.locator('input[type="checkbox"]')).not.toBeChecked();
  }
  await picker.getByTestId('short-make').click();
  await expect(page.getByTestId('bubble-user').last()).toContainText('0:01부터 0:04까지 숏폼으로 잘라줘');
  await expect(page.getByTestId('output-row')).toHaveCount(3, { timeout: 90_000 });
  const row = page.getByTestId('output-row').filter({ hasText: '숏폼 1' });
  await expect(row).toContainText('0:03');

  await row.getByRole('button', { name: '자세히' }).click();
  await expect(page).toHaveURL(/#\/outputs\//);
  const out = page.getByTestId('output-detail');
  await expect(out.getByRole('heading', { name: /숏폼 1/ })).toBeVisible();
  await expect(out.getByTestId('output-video')).toBeVisible();
  await expect(out.getByText('자막 없음')).toBeVisible();
  const dl = out.getByTestId('download');
  await expect(dl).toHaveAttribute('href', /\/media\/outputs\/.+\.mp4\?download=1/);
  const res = await page.request.head(await dl.getAttribute('href'));
  expect(res.status()).toBe(200);
  expect(res.headers()['content-disposition']).toContain('attachment');

  // PC 에서는 옆 패널이라 영상 채팅이 뒤에 그대로 있다. 닫으면 #/videos/ 로 돌아간다.
  await expect(page.getByTestId('video-detail')).toBeVisible();
  await out.getByTestId('panel-close').click();
  await expect(page).toHaveURL(/#\/videos\//);
  await expect(page.getByTestId('output-detail')).toHaveCount(0);
});

test('자막 넣기 (whisper 있을 때만): 자막 결과물과 자막 목록', async ({ page }) => {
  test.skip(!process.env['MADI_WHISPER_MODEL'] || !fs.existsSync(process.env['MADI_WHISPER_MODEL']), 'whisper 모델 없음');
  await page.goto('/');
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  await page.getByTestId('action-bar').locator('[data-action="subtitle"]').click();
  await expect(page.getByTestId('bubble-user').last()).toContainText('자막 넣어줘');
  await expect(page.getByTestId('progress-card')).toContainText('자막 만드는 중');
  await expect(page.getByTestId('output-row')).toHaveCount(4, { timeout: 180_000 });
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('자막을 넣었습니다');
  await page.getByTestId('output-row').filter({ hasText: '자막' }).getByRole('button', { name: '자세히' }).click();
  await expect(page.getByTestId('output-detail')).toBeVisible();
});

test('소리 없는 영상: "자막 직접 쓰기"로 원하는 자리에 자막을 넣는다 (AI 없이)', async ({ page }) => {
  fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(VIDEOS, '무음 시연.mp4'));
  await page.goto('/');
  const card = page.locator('[data-testid="video-card"]', { hasText: '무음 시연' });
  await expect(card).toHaveAttribute('data-status', 'ready', { timeout: 60_000 });
  await card.click();
  const bar = page.getByTestId('action-bar');
  await expect(bar.locator('[data-action="subtitle"]')).toBeDisabled(); // 소리 없고 자막도 없음
  await page.getByTestId('subtitle-editor-open').click();
  const editor = page.getByTestId('subtitle-editor');
  await expect(editor.getByTestId('subtitle-editor-row')).toHaveCount(1);
  // 원본 자막은 빈 채로 저장할 수 없다 (빈 자막이 생기면 "자막 만들기"가 음성 인식을 다시 안 돌린다)
  await editor.getByTestId('subtitle-editor-save').click();
  await expect(editor).toContainText('글을 한 줄 이상 써 주세요.');
  await editor.getByTestId('subtitle-editor-start').fill('0');
  await editor.getByTestId('subtitle-editor-end').fill('1.5');
  await editor.getByTestId('subtitle-editor-text').fill('무릎 펴기');
  await editor.getByTestId('subtitle-editor-add').click();
  const rows = editor.getByTestId('subtitle-editor-row');
  await expect(rows).toHaveCount(2);
  await rows.nth(1).getByTestId('subtitle-editor-text').fill('천천히');
  await editor.getByTestId('subtitle-editor-save').click();
  await expect(editor).toHaveCount(0);
  await expect(page.getByTestId('bubble-user').last()).toContainText('자막 넣어줘');
  await expect(page.getByTestId('output-row')).toHaveCount(1, { timeout: 90_000 });
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('자막을 넣었습니다');
  // 이제 자막 넣기 버튼도 살아 있다
  await expect(bar.locator('[data-action="subtitle"]')).toBeEnabled();
  // 결과물의 자막 목록에 그대로
  await page.getByTestId('output-row').getByRole('button', { name: '자세히' }).click();
  const out = page.getByTestId('output-detail');
  await expect(out.getByTestId('subtitle-row')).toHaveCount(2);
  await expect(out.getByTestId('subtitle-row').first()).toContainText('무릎 펴기');
  // AI 없이도 고칠 수 있다: 고른 줄 → 자막 고치기 → 편집기가 기존 줄로 열린다
  await out.getByTestId('subtitle-row').first().click();
  await out.getByTestId('subtitle-edit').click();
  await expect(page.getByTestId('subtitle-editor').getByTestId('subtitle-editor-row')).toHaveCount(2);
  await expect(page.getByTestId('subtitle-editor').getByTestId('subtitle-editor-text').first()).toHaveValue('무릎 펴기');
  for (const banned of ['transcript', '세그먼트', '렌더']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
});
