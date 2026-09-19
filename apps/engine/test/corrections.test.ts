/**
 * 용어 교정 — 순수 함수. 문장 전후에서 "틀린 말 → 바른 말"을 뽑고, 반복된 것을 자막에 적용한다 (기획안 §5.2 · §11).
 */
import { describe, expect, it } from 'vitest';
import type { Segment } from '@madi/shared';
import { applyCorrections, diffCorrections, pairsInLine } from '../src/style/corrections.js';

const seg = (id: string, start: number, end: number, text: string, words: string[] = []): Segment => ({
  id,
  start,
  end,
  text,
  words: words.map((w, i) => ({ start: start + i, end: start + i + 1, text: w, p: null })),
});

describe('pairsInLine', () => {
  it('낱말 하나가 다른 낱말로 바뀐 자리만 (조사는 같이 뗀다)', () => {
    expect(pairsInLine('겹갑골을 뒤로 모으고', '견갑골을 뒤로 모으고')).toEqual([{ wrong: '겹갑골', right: '견갑골' }]);
    expect(pairsInLine('외해전 하면서', '외회전 하면서')).toEqual([{ wrong: '외해전', right: '외회전' }]);
    expect(pairsInLine('겹갑골을 모으고', '견갑골이 모으고')).toEqual([{ wrong: '겹갑골', right: '견갑골' }]);
  });
  it('낱말이 더해지거나 빠진 것, 숫자, 한 글자, 같은 문장은 교정이 아니다', () => {
    expect(pairsInLine('천천히', '아주 천천히')).toEqual([]);
    expect(pairsInLine('열 번', '10 번')).toEqual([]);
    expect(pairsInLine('아 그리고', '어 그리고')).toEqual([]);
    expect(pairsInLine('같은 문장', '같은 문장')).toEqual([]);
    expect(pairsInLine('같은 문장', '같은  문장.')).toEqual([]);
  });
  it('아예 다른 낱말로 바꾸거나 문장을 다시 쓴 건 교정이 아니다 (잘못 들은 말은 바른 말과 닮았다)', () => {
    expect(pairsInLine('무릎 펴기', '겹갑골을 뒤로')).toEqual([]);
    expect(pairsInLine('무릎을 펴고 천천히', '어깨를 펴고 천천히')).toEqual([]);
    expect(pairsInLine('허리를 굽히지 말고 골반부터 접으세요', '허리를 굽히지 말고 고관절부터 접으세요')).toEqual([]);
  });
  it('한 문장에 둘 이상도', () => {
    expect(pairsInLine('겹갑골과 흉주를 펴고', '견갑골과 흉추를 펴고')).toEqual([
      { wrong: '겹갑골', right: '견갑골' },
      { wrong: '흉주', right: '흉추' },
    ]);
  });
});

describe('diffCorrections', () => {
  it('시각이 겹치는 문장끼리 견주고, 같은 쌍은 한 번만', () => {
    const before = [seg('a', 0, 2, '겹갑골을 모으고'), seg('b', 2, 4, '겹갑골이 아프면'), seg('c', 4, 6, '그대로')];
    const after = [seg('a', 0, 2, '견갑골을 모으고'), seg('b2', 2, 4, '견갑골이 아프면'), seg('c', 4, 6, '그대로'), seg('d', 6, 8, '새 문장')];
    expect(diffCorrections(before, after)).toEqual([{ wrong: '겹갑골', right: '견갑골' }]);
  });
});

describe('applyCorrections', () => {
  it('문장과 단어 둘 다 바꾸고 바꾼 수를 센다 (긴 말부터)', () => {
    const r = applyCorrections([seg('a', 0, 3, '겹갑골을 모으고 겹갑골', ['겹갑골을', '모으고', '겹갑골'])], [{ wrong: '겹갑골', right: '견갑골' }]);
    expect(r.replaced).toBe(4);
    expect(r.segments[0]!.text).toBe('견갑골을 모으고 견갑골');
    expect(r.segments[0]!.words.map((w) => w.text)).toEqual(['견갑골을', '모으고', '견갑골']);
    expect(applyCorrections([seg('a', 0, 1, 'x')], []).replaced).toBe(0);
  });
});
