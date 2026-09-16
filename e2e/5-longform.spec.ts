/**
 * 6단계 브라우저 e2e: 긴 영상 상세에 챕터·숏폼 버튼이 더 보이고, 챕터 나누기 → 챕터 카드 → "숏폼으로" → 결과물.
 * 긴 영상은 ffmpeg 로 만든다 (4장면 × 50초). AI 는 꺼 둔다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const VIDEOS = path.join(process.env['MADI_E2E_HOME']!, 'long-videos');

function ffmpegBin(): string {
  const require = createRequire(import.meta.url);
  return (require('@ffmpeg-installer/ffmpeg') as { path: string }).path;
}

test.describe.configure({ mode: 'serial', retries: 0 });

test('긴 영상: 버튼 6개, 챕터 나누기 → 챕터 4개 카드 → 숏폼으로 → 세로 결과물', async ({ page }) => {
  test.setTimeout(240_000);
  fs.mkdirSync(VIDEOS, { recursive: true });
  const file = path.join(VIDEOS, '햄스트링 풀버전.mp4');
  if (!fs.existsSync(file)) {
    const scenes = 4;
    const sec = 50;
    const colors = ['red', 'green', 'blue', 'yellow'];
    const inputs: string[] = [];
    const filter: string[] = [];
    for (let i = 0; i < scenes; i++) {
      inputs.push('-f', 'lavfi', '-i', `color=c=${colors[i]}:s=320x180:r=24:d=${sec}`, '-f', 'lavfi', '-i', `sine=frequency=${300 + i * 120}:sample_rate=44100:d=${sec}`);
      filter.push(`[${i * 2 + 1}:a]volume='if(lt(t,1)+gt(t,${sec - 1}),0,1)':eval=frame[a${i}]`);
    }
    filter.push(`${Array.from({ length: scenes }, (_, i) => `[${i * 2}:v]`).join('')}concat=n=${scenes}:v=1:a=0[v]`, `${Array.from({ length: scenes }, (_, i) => `[a${i}]`).join('')}concat=n=${scenes}:v=0:a=1[a]`);
    execFileSync(process.env['MADI_FFMPEG'] ?? ffmpegBin(), ['-hide_banner', '-y', ...inputs, '-filter_complex', filter.join(';'), '-map', '[v]', '-map', '[a]', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', file], { stdio: 'ignore', cwd: ROOT });
  }
  await page.request.patch('/api/settings', { data: { watchFolders: [VIDEOS], setupDone: true, ai: { provider: 'none' }, referenceFolders: [] } });
  await page.goto('/');
  const card = page.locator('[data-testid="video-card"]', { hasText: '햄스트링 풀버전' });
  await expect(card).toHaveAttribute('data-status', 'ready', { timeout: 120_000 });
  await card.click();

  const bar = page.getByTestId('action-bar');
  await expect(bar.getByRole('button')).toHaveCount(6);
  await bar.locator('[data-action="chapters"]').click();
  await expect(page.getByTestId('bubble-user').last()).toHaveText('챕터로 나눠줘');
  await expect(page.getByTestId('progress-card')).toContainText('챕터 나누는 중');
  const chapters = page.getByTestId('chapters-card');
  await expect(chapters).toBeVisible({ timeout: 120_000 });
  await expect(chapters.getByTestId('chapter-row')).toHaveCount(4);
  await expect(chapters).toContainText('챕터 4개');
  await expect(chapters.getByTestId('chapter-row').nth(1)).toContainText('2부');
  await expect(page.getByTestId('bubble-assistant').last()).toContainText('챕터 4개로 나눴어요');

  // 챕터 카드에서 바로 숏폼
  await chapters.getByTestId('chapter-short').nth(2).click();
  await expect(page.getByTestId('bubble-user').last()).toContainText('숏폼으로 잘라줘');
  await expect(page.getByTestId('output-row')).toHaveCount(1, { timeout: 120_000 });
  await expect(page.getByTestId('output-row')).toContainText('9:16');

  for (const banned of ['인코딩', '프록시', '트랜스크립트', '렌더', '세그먼트']) {
    await expect(page.getByText(banned, { exact: false })).toHaveCount(0);
  }
});
