import { describe, expect, it } from 'vitest';
import { chooseCropFocus, chooseSubtitleSide, motionDetectArgs, motionLevel, motionLevelIn, motionRegionsArgs, parseMotion, regionsFor, splitSilencesByMotion } from './motion.js';

const stderr = (rows: [number, number][]) =>
  rows.map(([t, y]) => `[Parsed_metadata_3 @ 0x1] frame:1 pts:1 pts_time:${t}\n[Parsed_metadata_3 @ 0x1] lavfi.signalstats.YDIF=${y}`).join('\n');

describe('motion', () => {
  it('화면만 작게 줄여 초당 4장, YDIF 를 찍는다', () => {
    const a = motionDetectArgs('/x.mp4');
    expect(a).toContain('-an');
    expect(a[a.indexOf('-vf') + 1]).toBe('fps=4,scale=160:-2,signalstats,metadata=print:key=lavfi.signalstats.YDIF');
    expect(a.slice(-2)).toEqual(['null', '-']);
  });

  it('metadata=print 를 시각 · 차이 쌍으로. 첫 장(0초)은 뺀다', () => {
    const s = parseMotion(stderr([
      [0, 0],
      [0.25, 0.4],
      [0.5, 5.2],
    ]));
    expect(s).toEqual([
      { t: 0.25, diff: 0.4 },
      { t: 0.5, diff: 5.2 },
    ]);
    expect(motionLevel(s, { start: 0.2, end: 0.3 })).toBe(0.4);
    expect(motionLevel(s, { start: 3, end: 4 })).toBeNull();
  });

  it('가만히 말하다 멈추고 동작을 보여 준 침묵은 남기고, 그냥 멈춘 침묵은 자른다', () => {
    // 0~4초 말함(움직임 0.5) · 4~7초 침묵인데 크게 움직임(6) · 7~9초 말함 · 9~10초 침묵인데 가만히(0.4)
    const rows: [number, number][] = [];
    for (let t = 0.25; t <= 10; t += 0.25) rows.push([t, t > 4 && t < 7 ? 6 : t > 9 ? 0.4 : 0.5]);
    const samples = parseMotion(stderr(rows));
    const r = splitSilencesByMotion([{ start: 4, end: 7 }, { start: 9, end: 10 }], samples, 10);
    expect(r.kept).toEqual([{ start: 4, end: 7 }]);
    expect(r.cut).toEqual([{ start: 9, end: 10 }]);
    expect(r.speechLevel).toBe(0.5);
  });

  it('처음부터 끝까지 똑같이 움직이는 영상(테스트 패턴 · 손떨림)은 전과 같이 다 자른다', () => {
    const rows: [number, number][] = [];
    for (let t = 0.25; t <= 8; t += 0.25) rows.push([t, 5 + (t % 1)]);
    const r = splitSilencesByMotion([{ start: 2, end: 4 }, { start: 6, end: 8 }], parseMotion(stderr(rows)), 8);
    expect(r.kept).toEqual([]);
    expect(r.cut).toHaveLength(2);
  });

  it('표본이 없거나 말한 구간이 없으면 전부 cut (판단 근거가 없다)', () => {
    expect(splitSilencesByMotion([{ start: 1, end: 2 }], [], 3).cut).toEqual([{ start: 1, end: 2 }]);
    const only = parseMotion(stderr([[1.5, 9]]));
    expect(splitSilencesByMotion([{ start: 1, end: 2 }], only, 2).kept).toEqual([]);
  });

  it('아주 정적인 영상에서 노이즈만으로는 남기지 않는다 (바닥값)', () => {
    const rows: [number, number][] = [];
    for (let t = 0.25; t <= 6; t += 0.25) rows.push([t, t > 3 ? 0.9 : 0.3]);
    const r = splitSilencesByMotion([{ start: 3, end: 6 }], parseMotion(stderr(rows)), 6);
    expect(r.kept).toEqual([]);
  });
});

describe('regions (세로 구도 · 자막 위치)', () => {
  it('가로 원본은 세 기둥 × 위아래 띠 여섯, 세로 원본은 위아래 둘', () => {
    const h = regionsFor(1920, 1080);
    expect(h.map((r) => r.name)).toEqual(['left.top', 'left.bottom', 'center.top', 'center.bottom', 'right.top', 'right.bottom']);
    expect(h[4]!.x + h[4]!.w).toBeCloseTo(1, 5);
    expect(h[2]!.x).toBeCloseTo(0.5 - h[2]!.w / 2, 5);
    expect(regionsFor(1080, 1920).map((r) => r.name)).toEqual(['top', 'bottom']);
  });

  it('한 번 훑어 조각마다 파일 하나에 쓴다', () => {
    const rs = regionsFor(1080, 1920);
    const a = motionRegionsArgs('/x.mp4', rs, ['/w/top.txt', '/w/bottom.txt']);
    const fc = a[a.indexOf('-filter_complex') + 1]!;
    expect(fc).toContain('split=2[s0][s1]');
    expect(fc).toContain("metadata=print:key=lavfi.signalstats.YDIF:file='/w/top.txt'[o0]");
    expect(fc).toContain('crop=w=2*floor(iw*1.0000/2):h=2*floor(ih*0.3800/2):x=2*floor(iw*0.0000/2):y=2*floor(ih*0.6200/2)');
    expect(a.filter((x) => x === '-map')).toHaveLength(2);
    expect(() => motionRegionsArgs('/x.mp4', rs, ['/one'])).toThrow();
  });

  it('여러 구간에 걸친 평균', () => {
    const s = parseMotion(stderr([[1, 2], [2, 4], [3, 9]]));
    expect(motionLevelIn(s, [{ start: 0.5, end: 1.5 }, { start: 2.5, end: 3.5 }])).toBe(5.5);
    expect(motionLevelIn(s, [])).toBeNull();
  });

  it('확실히 더 움직이는 기둥이 있을 때만 그쪽을 잡는다', () => {
    expect(chooseCropFocus({ left: 0.4, center: 0.5, right: 6 })).toBe(1);
    expect(chooseCropFocus({ left: 5, center: 1, right: 1 })).toBe(0);
    expect(chooseCropFocus({ left: 3, center: 2.9, right: 3.2 })).toBe(0.5); // 애매하면 가운데
    expect(chooseCropFocus({ left: 1.2, center: 0.1, right: 0.1 })).toBe(0.5); // 너무 조용하면 가운데
    expect(chooseCropFocus({ left: null, center: null, right: null })).toBe(0.5);
  });

  it('아래가 확실히 더 움직이면 자막은 위로, 아니면 아래', () => {
    expect(chooseSubtitleSide({ top: 0.5, bottom: 5 })).toBe('top');
    expect(chooseSubtitleSide({ top: 4, bottom: 5 })).toBe('bottom');
    expect(chooseSubtitleSide({ top: 0, bottom: 1 })).toBe('bottom');
    expect(chooseSubtitleSide({ top: null, bottom: null })).toBe('bottom');
  });
});
