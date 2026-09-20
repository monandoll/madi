import { expect, test } from '@playwright/test';

for (const width of [1280, 390]) {
  test(`${width}px: 참고 영상이 없어도 링크 도구 재확인 후 입력을 복구한다`, async ({ page, request }) => {
    await request.patch('/api/settings', { data: { setupDone: true, referenceFolders: [], ai: { provider: 'none' } } });
    const base = await (await request.get('/api/style')).json();
    let connected = false;
    await page.route('**/api/style', (route) => route.fulfill({ json: { ...base, references: [], linkImport: connected } }));
    await page.route('**/api/style/relearn', (route) => { connected = true; return route.fulfill({ json: { ...base, references: [], linkImport: true } }); });
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/#/settings');
    const section = page.getByTestId('style-section');
    await expect(section.getByTestId('relearn')).toHaveText('다시 확인');
    await expect(section).toContainText('링크 도구를 찾지 못했습니다');
    await expect(section).not.toContainText('다시 설치하세요');
    await section.getByTestId('relearn').click();
    await expect(section.getByTestId('link-input')).toBeEnabled();
    await expect(section).not.toContainText('링크 도구를 찾지 못했습니다');
    await section.getByTestId('link-input').fill('https://youtu.be/example');
    await expect(section.getByTestId('link-add')).toBeEnabled();
  });
}

test('스타일 관찰과 실제 화면 문구를 근거 시각과 함께 표시한다', async ({ page, request }) => {
  await request.patch('/api/settings', { data: { setupDone: true, ai: { provider: 'none' } } });
  const base = await (await request.get('/api/style')).json();
  const ref = { id: 'visual-ref', path: '/fixture.mp4', fileName: 'fixture.mp4', title: '스타일 검증 완성본', sizeBytes: 1, status: 'done', source: 'link', url: 'https://youtu.be/example', stats: null, excluded: false, error: null, createdAt: 1, updatedAt: 1, insight: { purpose: '시범 영상', audience: '', hook: '', tone: '', sections: [], keyPoints: [], keepRanges: [], cutCandidates: [], shortCandidates: [], terms: [], subtitleNotes: '', titleNote: '', visual: '', frameTimes: [2], tags: [], provider: 'claude', createdAt: 1, styleObservations: [{ category: 'captions', observation: '하단 한 줄 자막', evidence: 'visual', times: [2] }], onScreenText: [{ text: '천천히 당겨주세요', at: 2 }] } };
  await page.route('**/api/style', (route) => route.fulfill({ json: { ...base, references: [ref], insightOn: true, linkImport: true } }));
  await page.goto('/#/settings');
  await page.getByTestId('link-row').getByRole('button', { name: '메모', exact: true }).click();
  const insight = page.getByTestId('insight-view');
  await expect(insight).toContainText('하단 한 줄 자막 (화면 0:02)');
  await expect(insight).toContainText('0:02 “천천히 당겨주세요”');
});
