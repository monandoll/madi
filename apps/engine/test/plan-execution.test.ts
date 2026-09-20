import { expect, it } from 'vitest';
import { DEFAULT_SUBTITLE_STYLE, mergeSubtitleStyle, SubtitleStylePatch } from '@madi/shared';
import { parseRecipe } from '../src/plan/execution.js';
import { parsePlan, planBlock } from '../src/plan/prompt.js';
import { mergeSubtitleLines } from '../src/agent/subtitles.js';

it('실제 자막 설정·두 언어 문구·장면 순서를 저장하고 채팅 실행 지침에 넣는다', () => {
  const recipe = { summary: '시범 먼저, 2단 자막', parts: [{ start: 5, end: 10 }, { start: 0, end: 5 }], subtitleStyle: { background: 'outline', color: '#FFFFFF', bottom: 0.4, secondaryColor: '#FFE080', secondaryScale: 0.5 }, captions: [{ start: 0, end: 2, text: '팔을 당깁니다', secondaryText: 'Pull your arms.' }] };
  const plan = parsePlan(JSON.stringify({ purpose: '동작 안내', keepRanges: [{ start: 0, end: 10 }], recipe }), { videoId: 'v', provider: 'claude', durationSec: 10, fromTranscript: false, styleContextKey: 'approved-v1' })!;
  expect(plan.recipe).toMatchObject(recipe);
  expect(plan.styleContextKey).toBe('approved-v1');
  expect(planBlock(plan)).toContain('set_subtitle_text');
  expect(planBlock(plan)).toContain('secondaryText');
  expect(SubtitleStylePatch.parse({})).toEqual({});
  expect(mergeSubtitleStyle(DEFAULT_SUBTITLE_STYLE, { color: '#FFFFFF', fontSize: undefined })).toMatchObject({ color: '#FFFFFF', fontSize: DEFAULT_SUBTITLE_STYLE.fontSize });
});

it('시각 초과·겹친 순서·보존 구간 누락·잘못된 스타일은 실행하지 않는다', () => {
  expect(parseRecipe({ captions: [{ start: 0, end: 11, text: 'x' }] }, 10, [])).toBeNull();
  expect(parseRecipe({ parts: [{ start: 0, end: 5 }, { start: 4, end: 8 }] }, 10, [])).toBeNull();
  expect(parseRecipe({ parts: [{ start: 2, end: 8 }] }, 10, [{ start: 0, end: 3 }])).toBeNull();
  expect(parseRecipe({ subtitleStyle: { color: 'not-a-color' } }, 10, [])).toBeNull();
  expect(parsePlan('{"purpose":"x","recipe":{"subtitleStyle":{"bottom":3}}}', { videoId: 'v', provider: 'claude', durationSec: 10, fromTranscript: false })).toBeNull();
});

it('본문만 부분 수정하면 보조 문구를 유지하며, 명시적 빈 문자열로는 지울 수 있다', () => {
  const old = [{ id: 's', start: 0, end: 2, text: '처음', secondaryText: 'Original', words: [] }];
  expect(mergeSubtitleLines(old, [{ start: 0, end: 2, text: '수정' }])[0]!.secondaryText).toBe('Original');
  expect(mergeSubtitleLines(old, [{ start: 0, end: 2, text: '수정', secondaryText: '' }])[0]!.secondaryText).toBe('');
});
