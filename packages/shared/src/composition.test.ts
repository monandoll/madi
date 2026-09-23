import { describe, expect, it } from 'vitest';
import example from '../../../spike/composition.example.json' with { type: 'json' };
import { compositionDuration, parseComposition, sceneDuration, sceneOffsets } from './composition.js';

describe('Composition', () => {
  it('예시 컴포지션을 파싱한다', () => {
    const c = parseComposition(example);
    expect(c.scenes).toHaveLength(2);
    expect(c.templateId).toBe('suhyun.short.v1');
  });

  it('길이는 speed 를 반영한다', () => {
    const c = parseComposition(example);
    expect(compositionDuration(c)).toBeCloseTo(9.2, 3);

    const fast = parseComposition({
      ...example,
      scenes: [{ ...example.scenes[0], speed: 2 }],
    });
    expect(sceneDuration(fast.scenes[0]!)).toBeCloseTo(0.7, 3);
  });

  it('장면 오프셋은 누적된다', () => {
    expect(sceneOffsets(parseComposition(example))).toEqual([0, 1.4]);
  });

  // AGENTS.md §1-2 · §5: AI 가 스타일 값을 밀어 넣지 못하게 한다
  it('오버레이 payload 의 스타일 값을 거절한다', () => {
    const bad = {
      ...example,
      scenes: example.scenes.map((s, i) =>
        i === 0 ? { ...s, overlays: [{ ...s.overlays[0], payload: { text: 'x', fontSize: 99 } }] } : s,
      ),
    };
    expect(() => parseComposition(bad)).toThrow(/스타일 값/);
  });

  it('뒤집힌 시간 구간을 거절한다', () => {
    expect(() =>
      parseComposition({
        ...example,
        scenes: [
          {
            ...example.scenes[1],
            captions: [{ id: 'x', start: 2, end: 1, text: 'a', emphasis: [], slot: 'main' }],
          },
        ],
      }),
    ).toThrow();

    expect(() =>
      parseComposition({
        ...example,
        scenes: [{ ...example.scenes[0], source: { videoId: 'raw', in: 5, out: 5 } }],
      }),
    ).toThrow();
  });

  it('강조 구간이 text 범위를 넘으면 거절한다', () => {
    expect(() =>
      parseComposition({
        ...example,
        scenes: [
          {
            ...example.scenes[1],
            captions: [{ id: 'x', start: 0, end: 1, text: '짧다', emphasis: [{ from: 0, to: 99 }], slot: 'main' }],
          },
        ],
      }),
    ).toThrow();
  });

  it("mode 가 auto 가 아니면 keyframes 를 요구한다", () => {
    expect(() =>
      parseComposition({
        ...example,
        scenes: [
          { ...example.scenes[0], reframe: { mode: 'keyframes', padding: 0.08, keyframes: [] } },
        ],
      }),
    ).toThrow();
  });

  it('장면이 없으면 거절한다', () => {
    expect(() => parseComposition({ ...example, scenes: [] })).toThrow();
  });
});
