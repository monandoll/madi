import { describe, expect, it } from 'vitest';
import { keepSegments, remapRange, remapTime, totalDuration, emphasisTerms, splitEmphasis } from './edit.js';

describe('keepSegments', () => {
  it('전체에서 컷을 뺀다', () => {
    const segs = keepSegments({ keep: null, cuts: [{ start: 2, end: 3, reason: 'silence' }, { start: 5, end: 6, reason: 'silence' }] }, 10);
    expect(segs).toEqual([
      { start: 0, end: 2 },
      { start: 3, end: 5 },
      { start: 6, end: 10 },
    ]);
  });
  it('keep 구간 밖의 컷은 무시하고, 겹치는 컷은 합친다', () => {
    const segs = keepSegments(
      { keep: { start: 4, end: 9 }, cuts: [{ start: 1, end: 2, reason: 'manual' }, { start: 5, end: 7, reason: 'silence' }, { start: 6, end: 8, reason: 'silence' }] },
      10,
    );
    expect(segs).toEqual([
      { start: 4, end: 5 },
      { start: 8, end: 9 },
    ]);
  });
  it('길이를 넘는 keep 은 잘라낸다', () => {
    expect(keepSegments({ keep: { start: 8, end: 30 }, cuts: [] }, 10)).toEqual([{ start: 8, end: 10 }]);
    expect(keepSegments({ keep: { start: 12, end: 30 }, cuts: [] }, 10)).toEqual([]);
  });
});

describe('keepSegments · parts', () => {
  it('조각은 준 순서대로, 각 조각 안에서 컷을 뺀다', () => {
    const segs = keepSegments({ keep: { start: 0, end: 1 }, parts: [{ start: 5, end: 8 }, { start: 1, end: 3 }], cuts: [{ start: 6, end: 6.5, reason: 'ai' }] }, 10);
    expect(segs).toEqual([
      { start: 5, end: 6 },
      { start: 6.5, end: 8 },
      { start: 1, end: 3 },
    ]);
  });
  it('조각이 비어 있으면 keep 대로', () => {
    expect(keepSegments({ keep: { start: 2, end: 4 }, parts: [], cuts: [] }, 10)).toEqual([{ start: 2, end: 4 }]);
  });
  it('순서가 뒤바뀐 조각에서도 시각을 옮긴다', () => {
    const segs = [
      { start: 5, end: 8 },
      { start: 1, end: 3 },
    ];
    expect(remapTime(6, segs)).toBe(1);
    expect(remapTime(2, segs)).toBe(4);
    expect(remapTime(4, segs)).toBeNull();
    expect(remapRange({ start: 1.5, end: 2.5 }, segs)).toEqual({ start: 3.5, end: 4.5 });
  });
});

describe('remapTime', () => {
  const segs = [
    { start: 0, end: 2 },
    { start: 3, end: 5 },
  ];
  it('남는 구간 안의 시각을 이어 붙인 시각으로', () => {
    expect(remapTime(1, segs)).toBe(1);
    expect(remapTime(3.5, segs)).toBe(2.5);
    expect(remapTime(5, segs)).toBe(4);
  });
  it('잘린 구간은 null', () => {
    expect(remapTime(2.5, segs)).toBeNull();
    expect(remapTime(7, segs)).toBeNull();
  });
  it('총 길이', () => {
    expect(totalDuration(segs)).toBe(4);
  });
});

describe('remapRange', () => {
  const segs = [
    { start: 0, end: 2 },
    { start: 3, end: 5 },
  ];
  it('가운데가 남는 구간 안이면 살고, 경계에 걸치면 잘린다', () => {
    expect(remapRange({ start: 1, end: 2 }, segs)).toEqual({ start: 1, end: 2 });
    expect(remapRange({ start: 2, end: 3 }, segs)).toBeNull();
    expect(remapRange({ start: 2.5, end: 3.5 }, segs)).toEqual({ start: 2, end: 2.5 });
    expect(remapRange({ start: 1.4, end: 2.4 }, segs)).toEqual({ start: 1.4, end: 2 });
  });
});

describe('emphasis (자막 단어 강조)', () => {
  it('구간을 준 강조는 그 구간의 단어에만, 없는 건 전체에', () => {
    const em = [
      { term: '견갑골', start: 10, end: 20 },
      { term: '호흡', start: null, end: null },
    ];
    expect(emphasisTerms(em, { start: 12, end: 13 })).toEqual(['견갑골', '호흡']);
    expect(emphasisTerms(em, { start: 30, end: 31 })).toEqual(['호흡']);
  });

  it('글을 강조 조각으로 나눈다 (긴 단어 먼저, 겹치지 않게)', () => {
    expect(splitEmphasis('견갑골을 뒤로 모으고', ['견갑골'])).toEqual([
      { text: '견갑골', strong: true },
      { text: '을 뒤로 모으고', strong: false },
    ]);
    expect(splitEmphasis('외회전과 회전', ['회전', '외회전'])).toEqual([
      { text: '외회전', strong: true },
      { text: '과 ', strong: false },
      { text: '회전', strong: true },
    ]);
    expect(splitEmphasis('아무것도', [])).toEqual([{ text: '아무것도', strong: false }]);
    expect(splitEmphasis('', ['x'])).toEqual([]);
  });
});
