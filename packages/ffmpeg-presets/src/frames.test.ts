import { describe, expect, it } from 'vitest';
import { contactSheetArgs, FRAME_SHEET, frameSheets, pickFrameTimes } from './frames.js';

describe('frames (대표 프레임 시트)', () => {
  it('전체 표본에 장면 전환을 보충 — 가까운 표본은 중복하지 않고 앞뒤 0.2초는 피한다', () => {
    const t = pickFrameTimes(60, [0, 10, 10.3, 40]);
    expect(t[0]).toBe(0.2);
    expect(t.some((x) => Math.abs(x - 10.5) < 1)).toBe(true);
    expect(t).not.toContain(10.8);
    expect(t).toContain(40.5);
    expect(t.length).toBeGreaterThanOrEqual(6);
    for (const x of t) expect(x).toBeGreaterThanOrEqual(0.2);
    for (const x of t) expect(x).toBeLessThanOrEqual(59.8);
    expect([...t].sort((a, b) => a - b)).toEqual(t);
  });
  it('초반에 컷이 몰려도 중간·끝을 확인하고 유효한 시각만 선택한다', () => {
    const t = pickFrameTimes(600, [...Array.from({ length: 100 }, (_, i) => i / 2), NaN, Infinity, -1]);
    expect(t).toHaveLength(24);
    expect(t.some((x) => x > 250 && x < 350)).toBe(true);
    expect(t.at(-1)).toBe(599.8);
    expect(t.every((x) => Number.isFinite(x) && x >= 0.2 && x <= 599.8)).toBe(true);
    expect(pickFrameTimes(10, [], 0)).toEqual([]);
  });
  it('긴 영상도 최대 24장, 아주 짧은 영상은 0장', () => {
    expect(pickFrameTimes(1500, Array.from({ length: 200 }, (_, i) => i * 7)).length).toBe(FRAME_SHEET.perSheet * FRAME_SHEET.maxSheets);
    expect(pickFrameTimes(0.3, [])).toEqual([]);
    expect(pickFrameTimes(5, []).length).toBeGreaterThanOrEqual(3); // 1초 안에 붙은 칸은 하나로
  });
  it('시트는 12칸씩 2장까지', () => {
    const times = Array.from({ length: 30 }, (_, i) => i);
    const s = frameSheets(times);
    expect(s).toHaveLength(2);
    expect(s[0]).toHaveLength(12);
    expect(s[1]).toEqual(times.slice(12, 24));
  });
  it('시각마다 입력을 열어 한 장씩 뽑고 격자로 붙인다', () => {
    const a = contactSheetArgs({ input: '/v.mp4', output: '/o.jpg', times: [1, 2.5, 4, 6, 8] });
    expect(a.filter((x) => x === '-i')).toHaveLength(5);
    expect(a[a.indexOf('-ss') + 1]).toBe('1.000');
    const fc = a[a.indexOf('-filter_complex') + 1]!;
    expect(fc).toContain('[0:v]trim=end_frame=1,setpts=PTS-STARTPTS,scale=320:-2,setsar=1[f0]');
    expect(fc).toContain('concat=n=5:v=1:a=0,tile=4x2[out]');
    expect(a.slice(-1)).toEqual(['/o.jpg']);
    expect(() => contactSheetArgs({ input: '/v.mp4', output: '/o.jpg', times: [] })).toThrow();
  });
});
