import { describe, expect, it } from 'vitest';
import type { Segment } from '@madi/shared';
import { candidateBoundaries, chapterTitle, pickHighlight, pickShorts, splitChapters } from '../src/chapters/split.js';

/** t초부터 5초짜리 문장. gapAfter 만큼 쉬고 다음 문장. */
function sentences(spec: { text: string; at: number; len?: number }[]): Segment[] {
  return spec.map((s, i) => ({ id: `s${i}`, start: s.at, end: s.at + (s.len ?? 4), text: s.text, words: s.text.split(' ').map((w) => ({ start: s.at, end: s.at + 1, text: w, p: null })) }));
}

describe('chapters', () => {
  it('경계 후보: 문장 사이 쉼 + 장면 전환 + 무음', () => {
    const segs = sentences([
      { text: '안녕하세요', at: 0 },
      { text: '오늘은 햄스트링', at: 4.2 }, // 쉼 0.2 → 후보 아님
      { text: '먼저 준비운동', at: 10 }, // 쉼 1.8
      { text: '본운동 시작', at: 20 }, // 쉼 6 + 장면 + 무음
    ]);
    const c = candidateBoundaries(segs, [{ start: 14.5, end: 19.5 }], [19.9]);
    expect(c).toEqual([
      { at: 10, score: 1.8 },
      { at: 20, score: 4 + 2 + 1 },
    ]);
    // 자막 없으면 장면마다 (강한 경계)
    expect(candidateBoundaries([], [], [30, 61])).toEqual([
      { at: 30, score: 3 },
      { at: 61, score: 3 },
    ]);
  });

  it('길이 규칙: min 미만은 안 자르고, 강한 경계는 자르고, max 를 넘으면 가장 좋은 경계에서 자른다', () => {
    // 10분 영상, 문장이 60초마다 하나(쉼 56초 → 점수 4). 장면은 180, 360 근처.
    const segs = sentences(Array.from({ length: 10 }, (_, i) => ({ text: `문장 ${i + 1}`, at: i * 60 })));
    const ch = splitChapters({ segments: segs, silences: [], scenes: [180.5, 359.8], durationSec: 600 }, { minSec: 45, targetSec: 180, maxSec: 420 });
    // 60초 경계는 점수 4 → 강한 경계 → 60초마다 자른다 (min 45 넘음)
    expect(ch.map((c) => [c.start, c.end])).toEqual([
      [0, 60],
      [60, 120],
      [120, 180],
      [180, 240],
      [240, 300],
      [300, 360],
      [360, 420],
      [420, 480],
      [480, 540],
      [540, 600],
    ]);
    expect(ch[3]!.title).toBe('문장 4');
    // 약한 경계(쉼 1초)만 있으면 target 까지는 안 자르고, max 에서 가장 좋은 경계
    const weak = sentences(Array.from({ length: 40 }, (_, i) => ({ text: `문장 ${i + 1}`, at: i * 15, len: 14 })));
    const ch2 = splitChapters({ segments: weak, silences: [], scenes: [200], durationSec: 600 }, { minSec: 45, targetSec: 180, maxSec: 420 });
    // 장면 전환(200) 근처 문장 시작 195 → 점수 1+2=3 → 강한 경계. 그 뒤론 약한 경계뿐이라 끝까지 한 챕터 (405초 < max)
    expect(ch2.map((c) => [c.start, c.end])).toEqual([
      [0, 195],
      [195, 600],
    ]);
    // 약한 경계만 있고 max 를 넘기면 target 넘긴 뒤 가장 좋은 곳(같으면 뒤쪽)에서 자른다
    const ch3 = splitChapters({ segments: weak, silences: [], scenes: [], durationSec: 600 }, { minSec: 45, targetSec: 180, maxSec: 420 });
    expect(ch3.map((c) => [c.start, c.end])).toEqual([
      [0, 420],
      [420, 600],
    ]);
  });

  it('마지막 조각이 짧으면 앞 챕터에 붙고, 짧은 영상은 챕터 하나', () => {
    const segs = sentences([
      { text: '하나', at: 0 },
      { text: '둘', at: 60 },
      { text: '셋', at: 110 },
    ]);
    const ch = splitChapters({ segments: segs, silences: [], scenes: [], durationSec: 130 }, { minSec: 45, targetSec: 180, maxSec: 420 });
    expect(ch.map((c) => [c.start, c.end])).toEqual([
      [0, 60],
      [60, 130],
    ]);
    expect(splitChapters({ segments: [], silences: [], scenes: [], durationSec: 30 })).toEqual([{ index: 0, title: '1부', start: 0, end: 30, highlight: { start: 0, end: 30 } }]);
    expect(splitChapters({ segments: [], silences: [], scenes: [], durationSec: 0 })).toEqual([]);
  });

  it('제목: 첫 문장 24자, 자막 없으면 N부', () => {
    expect(chapterTitle(sentences([{ text: '허리를 굽히지 말고 골반부터 접으세요 그리고 무릎을 펴세요', at: 0 }]), 2)).toBe('허리를 굽히지 말고 골반부터 접으세요 그리…');
    expect(chapterTitle([], 2)).toBe('3부');
  });

  it('하이라이트: 챕터가 60초 이하면 통째로, 길면 말이 빽빽한 40초 창을 문장 경계에 맞춰', () => {
    expect(pickHighlight([], { start: 10, end: 50 })).toEqual({ start: 10, end: 50 });
    expect(pickHighlight([], { start: 0, end: 10 })).toBeNull();
    // 0~120 챕터: 앞 60초는 문장이 드문드문, 60~100 은 4초마다 문장
    const segs = sentences([
      { text: '가', at: 0 },
      { text: '나', at: 30 },
      ...Array.from({ length: 10 }, (_, i) => ({ text: `다 ${i} 라 마 바`, at: 60 + i * 4, len: 3.5 })),
    ]);
    const h = pickHighlight(segs, { start: 0, end: 120 })!;
    expect(h.start).toBeCloseTo(59.7, 1);
    expect(h.end).toBeLessThanOrEqual(100);
    expect(h.end - h.start).toBeGreaterThanOrEqual(15);
    // 자막 없는 긴 챕터는 앞 40초
    expect(pickHighlight([], { start: 100, end: 300 })).toEqual({ start: 100, end: 140 });
  });

  it('자동 숏폼은 하이라이트 있는 챕터에서 순서대로 max 개', () => {
    const ch = splitChapters({ segments: [], silences: [], scenes: [60, 120, 180], durationSec: 240 });
    expect(ch).toHaveLength(4);
    expect(pickShorts(ch, 2)).toEqual([
      { title: '1부', range: { start: 0, end: 60 } },
      { title: '2부', range: { start: 60, end: 120 } },
    ]);
  });
});
