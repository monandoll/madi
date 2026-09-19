/**
 * 5단계 브라우저 e2e: 설정 · 편집 스타일 — 규칙 추가/빼기, 완성본 폴더 고르기 → 배운 줄이 붙는다.
 * 완성본 폴더는 엔진의 후보 목록(MADI_SUGGEST_ROOT 아래 Desktop)을 쓴다. 갤러리 스펙은 이미 끝났으므로 Desktop 에 영상을 넣어도 된다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'fixtures');
const DESKTOP = path.join(process.env['MADI_E2E_HOME']!, 'suggest', 'Desktop');

test.describe.configure({ mode: 'serial', retries: 0 });

test('편집 스타일: 규칙을 더하고 뺀다', async ({ page }) => {
  await page.request.patch('/api/settings', { data: { referenceFolders: [], ai: { provider: 'none' }, setupDone: true } });
  await page.goto('/#/settings');
  const section = page.getByTestId('style-section');
  await expect(section).toBeVisible();
  const before = await section.getByTestId('style-rule').count();
  expect(before).toBeGreaterThan(0);
  await section.getByTestId('style-rule-input').fill('인트로는 3초만');
  await section.getByTestId('style-rule-add').click();
  await expect(section.getByTestId('style-rule')).toHaveCount(before + 1);
  const added = section.getByTestId('style-rule').filter({ hasText: '인트로는 3초만' });
  await expect(added).toHaveAttribute('data-learned', 'false');
  await added.getByRole('button', { name: '빼기' }).click();
  await expect(section.getByTestId('style-rule')).toHaveCount(before);
  // 전문 용어 금지
  for (const banned of ['인코딩', '프록시', '트랜스크립트', '렌더']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
});

test('완성본 폴더를 고르면 분석해서 배운 줄이 붙는다', async ({ page }) => {
  fs.mkdirSync(DESKTOP, { recursive: true });
  fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(DESKTOP, '햄스트링 완성.mp4'));
  fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(DESKTOP, '어깨 루틴_final.mp4'));
  await page.goto('/#/settings');
  const refs = page.getByTestId('references-section');
  await expect(refs).toContainText('기존 영상으로 배우기');
  await refs.getByRole('button', { name: '폴더 추가…' }).click();
  await refs.getByRole('checkbox', { name: /바탕화면/ }).click();
  await expect(refs.getByTestId('reference-folders')).toContainText('Desktop');
  await expect(refs.getByTestId('references-status')).toHaveText('완성본 2개', { timeout: 90_000 });
  const learned = page.getByTestId('style-section').locator('[data-testid="style-rule"][data-learned="true"]');
  await expect(learned.first()).toContainText('(배움) 완성본 2개 기준: 가로 16:9');
  await expect(learned.first()).toContainText('배움');
  // 배운 줄엔 빼기가 없다
  await expect(learned.first().getByRole('button', { name: '빼기' })).toHaveCount(0);

  // 폴더를 빼면 배운 줄도 사라진다
  await refs.getByTestId('reference-folders').getByRole('button', { name: '빼기' }).click();
  await expect(learned).toHaveCount(0);
  await expect(refs.getByTestId('references-status')).toHaveText('');
});

test('링크를 붙여 넣으면 받아서 배운다 (가짜 yt-dlp)', async ({ page }) => {
  await page.goto('/#/settings');
  const refs = page.getByTestId('references-section');
  const input = refs.getByTestId('link-input');
  // 주소가 아니면 가져오기가 눌리지 않는다
  await input.fill('햄스트링 루틴');
  await expect(refs.getByTestId('link-add')).toBeDisabled();
  await input.fill('https://www.youtube.com/shorts/gaps');
  await refs.getByTestId('link-add').click();
  const row = refs.getByTestId('link-row').first();
  await expect(row).toContainText('유튜브');
  await expect(row.getByTestId('link-status')).toHaveText('배움', { timeout: 60_000 });
  await expect(row).toContainText('gaps');
  await expect(input).toHaveValue('');
  const learned = page.getByTestId('style-section').locator('[data-testid="style-rule"][data-learned="true"]');
  await expect(learned.first()).toContainText('완성본 1개 기준');

  // 못 가져오는 링크는 이유가 AI 말투로
  await input.fill('https://www.instagram.com/reel/private');
  await refs.getByTestId('link-add').click();
  const bad = refs.getByTestId('link-row').filter({ hasText: '인스타그램' });
  await expect(bad.getByTestId('link-status')).toHaveText('못 읽음', { timeout: 30_000 });
  await expect(bad).toContainText('로그인해야 볼 수 있는 영상');
  // 전문 용어 금지
  for (const banned of ['yt-dlp', '다운로드', 'URL']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
  // 빼면 배운 값도 사라진다
  await bad.getByTestId('link-remove').click();
  await expect(refs.getByTestId('link-row')).toHaveCount(1);
  await refs.getByTestId('link-row').first().getByTestId('link-remove').click();
  await expect(refs.getByTestId('link-row')).toHaveCount(0);
  await expect(learned).toHaveCount(0);
});

test('자막에서 고친 말: 두 번 고치면 "바로 바꿈", 빼면 사라진다', async ({ page }) => {
  // 준비된 영상이 하나 필요하다. 이 스펙만 따로 돌리면 갤러리 스펙이 안 돌았을 수 있으니 폴더 하나를 더 본다.
  const readyVideo = async () => ((await (await page.request.get('/api/videos')).json()).videos as { id: string; status: string }[]).find((x) => x.status === 'ready');
  if (!(await readyVideo())) {
    const dir = path.join(process.env['MADI_E2E_HOME']!, 'corrections-videos');
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(dir, '고친 말.mp4'));
    const { settings } = await (await page.request.get('/api/settings')).json();
    await page.request.patch('/api/settings', { data: { watchFolders: [...settings.watchFolders, dir] } });
    await expect.poll(readyVideo, { timeout: 60_000 }).toBeTruthy();
  }
  const v = (await readyVideo())!;
  const put = (text: string) => page.request.put(`/api/videos/${v.id}/transcript`, { data: { segments: [{ start: 0, end: 1, text }] } });
  await put('겹갑골을 모으고');
  await put('견갑골을 모으고');
  await page.goto('/#/settings');
  const sec = page.getByTestId('corrections-section');
  await expect(sec).toBeVisible();
  const row = sec.getByTestId('correction-row').filter({ hasText: '견갑골' });
  await expect(row).toContainText('겹갑골');
  await expect(row).toContainText('1번 고침');
  // 문장을 아예 바꾼 건 교정이 아니다 → 새 문장에서 같은 말을 또 고치면 2번
  await put('허리를 펴세요');
  await put('겹갑골이 아프면');
  await put('견갑골이 아프면');
  await page.reload();
  await expect(sec.getByTestId('correction-row').filter({ hasText: '견갑골' })).toContainText('2번 고침 · 바로 바꿈');
  await sec.getByTestId('correction-row').filter({ hasText: '견갑골' }).getByTestId('correction-remove').click();
  await expect(page.getByTestId('corrections-section')).toHaveCount(0);
});

test('AI 가 기억한 것: 직접 한 줄 쓰면 바로 쓰이고, 고치고, 빼고, 전부 지운다', async ({ page }) => {
  await page.request.patch('/api/settings', { data: { ai: { provider: 'none' }, setupDone: true } });
  await page.goto('/#/settings');
  // 밖으로 나가는 것을 알려 준다 (기획안 §12)
  await expect(page.getByTestId('ai-data-notice')).toContainText('영상 파일은 이 컴퓨터를 떠나지 않습니다');
  const mem = page.getByTestId('memory-section');
  await expect(mem).toBeVisible();
  await expect(mem.getByTestId('memory-list')).toContainText('아직 기억한 것이 없습니다');
  await expect(mem.getByTestId('memory-proposed')).toHaveCount(0);
  await mem.getByTestId('memory-input').fill('도입은 질문으로 연다');
  await mem.getByTestId('memory-add').click();
  const row = mem.getByTestId('memory-row').filter({ hasText: '도입은 질문으로 연다' });
  await expect(row).toBeVisible();
  await expect(row).toHaveAttribute('data-scope', 'all');
  await expect(row).toHaveAttribute('data-status', 'approved');
  await expect(row.getByTestId('memory-approve')).toHaveCount(0);
  await expect(row).toContainText('모든 영상 · 직접');
  // 고치기
  await row.getByTestId('memory-edit').click();
  // 고치는 동안은 글이 입력칸 안에 있어 hasText 로는 못 찾는다
  await mem.getByTestId('memory-edit-input').fill('도입은 질문 하나로 연다');
  await mem.getByTestId('memory-edit-input').press('Enter');
  await expect(mem.getByTestId('memory-row').filter({ hasText: '도입은 질문 하나로 연다' })).toBeVisible();
  // 하나 더 쓰고 전부 지우기 (두 번 눌러야 지워진다)
  await mem.getByTestId('memory-input').fill('시범은 끝까지');
  await mem.getByTestId('memory-add').click();
  await expect(mem.getByTestId('memory-row')).toHaveCount(2);
  await mem.getByTestId('memory-clear').click();
  await expect(mem.getByTestId('memory-clear-confirm')).toContainText('되돌릴 수 없습니다');
  await mem.getByTestId('memory-clear-yes').click();
  await expect(mem.getByTestId('memory-row')).toHaveCount(0);
  await expect(mem.getByTestId('memory-clear')).toHaveCount(0);
  // 전문 용어 금지
  for (const banned of ['인사이트', '임베딩', '메모리', '프롬프트']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
});
