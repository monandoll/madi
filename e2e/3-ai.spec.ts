/**
 * 4단계 브라우저 e2e: 설정에서 AI 도구 고르기 → 상세의 칩·입력창 → 채팅 → 스트리밍 답 → 도구가 만든 결과물 카드.
 * 파일 이름 숫자 순으로 마지막에 돈다 (앞 스펙의 결과물 개수 검증을 건드리지 않게). 자기 폴더(ai-videos)에 영상을 넣고 시작하며, 끝나면 연결을 끊는다.
 * AI 는 fixtures/fake-claude.mjs (MADI_CLAUDE_BIN) — MCP 도구 호출은 진짜로 오간다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURES = path.join(ROOT, 'fixtures');
const VIDEOS = path.join(process.env['MADI_E2E_HOME']!, 'ai-videos');

test.describe.configure({ mode: 'serial', retries: 0 });

test('설정: 설치된 도구 중 Claude Code 를 고르면 연결됨', async ({ page }) => {
  fs.mkdirSync(VIDEOS, { recursive: true });
  fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(VIDEOS, '어깨 가동성 루틴 3분.mp4'));
  await page.request.patch('/api/settings', { data: { watchFolders: [VIDEOS], setupDone: true, workspaceName: '재활운동 연구소', ai: { provider: 'none' } } });
  await page.goto('/');
  await expect(page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' })).toHaveAttribute('data-status', 'ready', { timeout: 60_000 });

  await page.goto('/#/settings');
  const ai = page.getByTestId('ai-section');
  await expect(ai.getByTestId('ai-status')).toHaveText('연결 안 됨');
  const claude = ai.getByTestId('ai-provider-claude');
  await expect(claude).toContainText('Claude Code');
  await expect(claude).toContainText('설치됨 · 9.9.9');
  await claude.getByRole('button', { name: '연결하기' }).click();
  await expect(ai.getByTestId('ai-status')).toHaveText('Claude Code 연결됨');
  await expect(claude).toContainText('연결됨');
  await expect(claude.getByTestId('ai-disconnect')).toBeVisible();
  // 사이드바 아래 표시. 붉은색 없이 조용하게.
  await page.goto('/');
  await expect(page.getByTestId('sidebar').getByText('Claude Code 연결됨')).toBeVisible();
});

test('상세: 입력창과 칩이 보이고, 말로 시키면 답이 채워지며 결과물 카드가 붙는다', async ({ page }) => {
  await page.goto('/');
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  const detail = page.getByTestId('video-detail');
  await expect(detail).toHaveAttribute('data-ai', 'on');
  await expect(page.getByTestId('action-bar')).toHaveCount(0);
  const bar = page.getByTestId('chat-bar');
  await expect(bar.getByTestId('chat-chip')).toHaveCount(4);
  await expect(bar.getByTestId('chat-chip').first()).toHaveText('숏폼 뽑아줘');
  const input = page.getByPlaceholder('말로 요청하세요');
  await expect(input).toBeVisible();
  const before = await page.getByTestId('output-row').count();

  await input.fill('세로로 바꿔줘');
  await page.getByTestId('chat-send').click();
  await expect(page.getByTestId('bubble-user').last()).toHaveText('세로로 바꿔줘');
  await expect(page.getByTestId('chat-stop')).toBeVisible(); // 답하는 동안은 멈추기
  // 쓰는 중인 말풍선에 글자가 차오른다
  await expect(page.getByTestId('bubble-streaming')).toContainText('세로로 만들게요', { timeout: 30_000 });
  // 도구가 만든 진행 카드 → 결과물 카드 (답 말풍선 아래에 붙는다)
  await expect(page.getByTestId('output-row')).toHaveCount(before + 1, { timeout: 90_000 });
  await expect(page.getByTestId('output-row').last()).toContainText('AI 세로');
  await expect(page.getByTestId('bubble-assistant').filter({ hasText: '「AI 세로」 만들었어요' })).toHaveCount(2); // 답 + 카드 설명
  await expect(page.getByTestId('chat-send')).toBeVisible({ timeout: 30_000 });
  await expect(page.getByTestId('bubble-streaming')).toHaveCount(0);

  // 도구 호출 내부는 안 보인다
  for (const banned of ['apply_edit', 'render', 'mcp', 'tool_use', '인코딩', '트랜스크립트']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }

  // 칩은 그 말을 그대로 보낸다 (가짜 CLI 는 규칙을 읽었다고 답한다 = style.md 주입 확인)
  await bar.getByTestId('chat-chip').first().click();
  await expect(page.getByTestId('bubble-user').last()).toHaveText('숏폼 뽑아줘');
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('규칙 읽었어요', { timeout: 30_000 });

  // 결과물 카드의 수정 요청 → 입력창에 미리 채워진다
  await page.getByTestId('output-row').last().getByTestId('output-revise').click();
  await expect(input).toHaveValue('「AI 세로」 고쳐줘: ');
  await input.fill('');
});

test('멈추기: 답하는 중에 멈추면 그때까지의 말만 남는다', async ({ page }) => {
  await page.goto('/');
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  const input = page.getByPlaceholder('말로 요청하세요');
  await input.fill('느리게 해줘');
  await input.press('Enter');
  await expect(page.getByTestId('bubble-streaming')).toContainText('천천히 할게요', { timeout: 30_000 });
  await page.getByTestId('chat-stop').click();
  await expect(page.getByTestId('chat-send')).toBeVisible();
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('천천히 할게요.');
  await expect(page.getByTestId('bubble-assistant').last()).not.toContainText('다 했어요');
});

test('설정에서 연결을 끊으면 다시 버튼 4개', async ({ page }) => {
  await page.goto('/#/settings');
  await page.getByTestId('ai-disconnect').click();
  await expect(page.getByTestId('ai-status')).toHaveText('연결 안 됨');
  await page.goto('/');
  await expect(page.getByText('AI 연결 안 됨')).toBeVisible();
  await page.locator('[data-testid="video-card"]', { hasText: '어깨 가동성 루틴 3분' }).click();
  await expect(page.getByTestId('action-bar').getByRole('button')).toHaveCount(4);
  await expect(page.getByTestId('chat-bar')).toHaveCount(0);
});
