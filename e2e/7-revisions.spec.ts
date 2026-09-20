import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let videoId: string;
let original: any;

test('편집안에서 반영할 방식·장면 순서·2단 자막 수·미지원 항목을 확인한다', async ({ page, request }) => {
  const data = await (await request.get(`/api/videos/${videoId}`)).json();
  const plan = { videoId, purpose: '동작 설명', hook: '', audience: '', sections: [], keepRanges: [], cutCandidates: [], shortCandidates: [], terms: [], tags: [], fromTranscript: false, feedback: [], framing: null, frameTimes: [], provider: 'claude', createdAt: 1, styleContextKey: '', recipe: { summary: '시범 먼저, 짧은 2단 자막', parts: [{ start: 1.5, end: 3 }, { start: 0, end: 1.5 }], subtitleStyle: { background: 'outline' }, captions: [{ start: 0, end: 1, text: '천천히', secondaryText: 'Slowly' }], limitations: ['화살표는 아직 지원하지 않습니다.'] } };
  const message = { id: 'plan-qa', videoId, role: 'assistant', kind: 'plan', code: 'plan.ready', params: {}, jobId: null, outputId: null, createdAt: 1, updatedAt: 1 };
  await page.route(`**/api/videos/${videoId}`, route => route.fulfill({ json: { ...data, plan, messages: [message] } }));
  await page.goto(`/#/videos/${videoId}`);
  const recipe = page.getByTestId('plan-recipe');
  await expect(recipe).toContainText('시범 먼저, 짧은 2단 자막');
  await expect(recipe).toContainText('보조 문구 1개');
  await expect(recipe).toContainText('화살표는 아직 지원하지 않습니다.');
});
test.describe.configure({ mode: 'serial', retries: 0 });

test.beforeAll(async ({ request }) => {
  const folder = path.join(process.env['MADI_E2E_HOME']!, 'revisions');
  fs.mkdirSync(folder, { recursive: true });
  fs.copyFileSync(path.join(ROOT, 'fixtures/sample-silent-3s.mp4'), path.join(folder, '자막 버전 시연.mp4'));
  await request.patch('/api/settings', { data: { watchFolders: [folder], setupDone: true, ai: { provider: 'none' } } });
  await expect.poll(async () => {
    const data = await (await request.get('/api/videos')).json();
    const video = data.videos.find((v: any) => v.title === '자막 버전 시연' && v.status === 'ready');
    videoId = video?.id;
    return !!video;
  }, { timeout: 60_000 }).toBe(true);
  await request.put(`/api/videos/${videoId}/transcript`, { data: { segments: [{ start: 0.5, end: 1.5, text: '처음 안내 문구', secondaryText: 'Original guidance' }] } });
  await request.post(`/api/videos/${videoId}/actions`, { data: { type: 'short', range: { start: 0.5, end: 2.5 }, subtitles: true } });
  await expect.poll(async () => (await (await request.get(`/api/videos/${videoId}`)).json()).outputs.length, { timeout: 60_000 }).toBe(1);
  const id = (await (await request.get(`/api/videos/${videoId}`)).json()).outputs[0].id;
  original = await (await request.get(`/api/outputs/${id}`)).json();
  // 원본 자막을 바꿔도 선택한 과거 결과의 편집기에는 영향을 주면 안 된다.
  await request.put(`/api/videos/${videoId}/transcript`, { data: { segments: [{ start: 0.5, end: 1.5, text: '원본의 다른 문구' }] } });
});

for (const width of [1280, 390]) {
  test(`${width}px: 선택한 숏폼의 문구만 수정하고 최신 결과와 이전 버전을 확인한다`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`/#/outputs/${original.output.id}`);
    const out = page.getByTestId('output-detail');
    await expect(out.getByTestId('subtitle-row')).toContainText('처음 안내 문구');
    await out.getByTestId('subtitle-row').click();
    await out.getByTestId('subtitle-edit').click();
    await expect(page).toHaveURL(new RegExp(`#/videos/${videoId}$`));
    const editor = page.getByTestId('subtitle-editor');
    await expect(editor.getByTestId('subtitle-editor-text')).toHaveValue('처음 안내 문구');
    await expect(editor.getByTestId('subtitle-editor-secondary')).toHaveValue('Original guidance');
    await editor.getByTestId('subtitle-editor-text').fill(`수정한 안내 ${width}`);
    const putRequest = page.waitForRequest(r => r.method() === 'PUT' && r.url().endsWith('/transcript'));
    await editor.getByTestId('subtitle-editor-save').click();
    expect((await putRequest).postDataJSON().editId).toBe(original.edit.id);
    await expect(editor).toHaveCount(0);
    const count = width === 1280 ? 2 : 3;
    await expect(page.getByTestId('output-row')).toHaveCount(count, { timeout: 60_000 });
    const detail = await (await page.request.get(`/api/videos/${videoId}`)).json();
    const latest = detail.outputs[0];
    const revised = await (await page.request.get(`/api/outputs/${latest.id}`)).json();
    expect(revised.edit).toMatchObject({ keep: original.edit.keep, crop: original.edit.crop, revisionOf: original.edit.id });
    expect(revised.transcript.segments[0].secondaryText).toBe('Original guidance');
    expect(revised.output).toMatchObject({ width: 1080, height: 1920 });
    expect(Math.abs(revised.output.durationSec - original.output.durationSec)).toBeLessThan(0.1);
    if (width === 1280) await page.getByTestId('panel-toggle').click();
    else await page.getByRole('button', { name: '결과물', exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`#/outputs/${latest.id}$`));
    await expect(out.getByTestId('subtitle-row')).toContainText(`수정한 안내 ${width}`);
    // 번인된 MP4 위에 HTML 문구를 다시 얹지 않는다.
    await expect(out.getByTestId('output-video').locator('..')).toHaveText('');
    expect((await page.request.head((await out.getByTestId('download').getAttribute('href'))!)).status()).toBe(200);
    await page.screenshot({ path: `test-results/revisions-${width}.png` });
    const before = await (await page.request.get(`/api/outputs/${original.output.id}`)).json();
    expect(before.transcript.segments[0].text).toBe('처음 안내 문구');
  });

  test(`${width}px: AI 수정 요청에도 선택한 결과 버전을 전달한다`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.route('**/api/health', async route => {
      const response = await route.fetch();
      const body = await response.json();
      await route.fulfill({ json: { ...body, ai: { provider: 'claude', installed: true, connected: true } } });
    });
    // UI→API 계약만 검사한다. 실제 AI 품질은 이 테스트의 대상이 아니다.
    await page.route(`**/api/videos/${videoId}/chat`, route => route.fulfill({ json: { messages: [] } }));
    await page.goto(`/#/outputs/${original.output.id}`);
    const revise = page.getByTestId('output-detail').getByTestId('output-revise');
    await expect(revise).toBeEnabled();
    await revise.click();
    const input = page.getByTestId('chat-input');
    await expect(input).not.toHaveValue('');
    await input.fill('문구를 천천히 움직이세요로 고쳐줘');
    const sending = page.waitForRequest(r => r.url().endsWith('/chat') && r.method() === 'POST');
    await input.press('Enter');
    expect((await sending).postDataJSON()).toMatchObject({ editId: original.edit.id, text: '문구를 천천히 움직이세요로 고쳐줘' });
  });
}
