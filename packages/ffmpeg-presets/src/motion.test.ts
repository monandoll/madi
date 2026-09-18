import { describe, expect, it } from 'vitest';
import { motionDetectArgs, motionLevel, parseMotion, splitSilencesByMotion } from './motion.js';

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
