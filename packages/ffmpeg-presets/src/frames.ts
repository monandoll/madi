/**
 * 대표 프레임 시트 — 기획안 §10 "장면 전환 지점과 중요한 설명 구간의 대표 프레임을 추출한다".
 *
 * 영상을 통째로 보여 주지 않는다. 장면이 바뀐 직후와 고르게 나눈 지점에서 한 장씩 뽑아 작은 칸으로 모아 붙인 시트(최대 2장)를
 * AI 에게 준다. 칸마다 시각을 화면에 찍지 않고(폰트 · drawtext 의존을 피한다) 프롬프트에 "칸 순서대로 시각" 을 적는다.
 */

export const FRAME_SHEET = {
  /** 시트 한 장에 몇 칸 */
  perSheet: 12,
  /** 한 줄에 몇 칸 */
  cols: 4,
  /** 칸 너비(px). 4칸이면 1280 너비 — 사람이 어디 있는지 · 앵글이 보이면 된다 */
  tileWidth: 320,
  /** 영상 하나에 시트 몇 장까지 (토큰) */
  maxSheets: 2,
} as const;

/**
 * 어느 시각의 화면을 볼지. 장면 전환 직후(+0.5초)를 먼저, 모자라면 고르게 나눈 지점을 더한다.
 * 서로 1초 안에 붙은 것은 하나로. 앞뒤 0.2초는 피한다.
 */
export function pickFrameTimes(durationSec: number, scenes: number[], max = FRAME_SHEET.perSheet * FRAME_SHEET.maxSheets): number[] {
  const dur = Math.max(0, durationSec);
  if (dur <= 0.4) return [];
  const lo = 0.2;
  const hi = Math.max(lo, dur - 0.2);
  const clamp = (t: number) => Math.min(hi, Math.max(lo, t));
  const out: number[] = [];
  const add = (t: number) => {
    const c = clamp(t);
    if (out.some((x) => Math.abs(x - c) < 1)) return;
    out.push(c);
  };
  for (const s of [...scenes].sort((a, b) => a - b)) {
    if (out.length >= max) break;
    add(s + 0.5);
  }
  // 고르게: 20초에 한 장쯤, 최소 6장, max 이하
  const target = Math.min(max, Math.max(6, Math.round(dur / 20)));
  const evenly = Math.min(target, Math.max(1, Math.round(dur / 0.9)));
  for (let i = 0; i < evenly && out.length < target; i++) add(((i + 0.5) / evenly) * dur);
  return out.sort((a, b) => a - b).map((t) => Math.round(t * 10) / 10);
}

/** 시각 목록 → 시트별 묶음 (perSheet 씩, maxSheets 장까지). */
export function frameSheets(times: number[], per = FRAME_SHEET.perSheet, maxSheets = FRAME_SHEET.maxSheets): number[][] {
  const out: number[][] = [];
  for (let i = 0; i < times.length && out.length < maxSheets; i += per) out.push(times.slice(i, i + per));
  return out;
}

export interface ContactSheetOptions {
  input: string;
  output: string;
  /** 칸 순서대로 시각(초) */
  times: number[];
  cols?: number;
  tileWidth?: number;
}

/**
 * 시각마다 한 장씩 뽑아(입력을 시각 수만큼 연다, 빠른 탐색) 같은 너비로 줄인 뒤 격자로 붙인 JPEG 하나.
 * 칸이 격자를 다 못 채우면 남는 칸은 검게 남는다.
 */
export function contactSheetArgs({ input, output, times, cols = FRAME_SHEET.cols, tileWidth = FRAME_SHEET.tileWidth }: ContactSheetOptions): string[] {
  if (times.length === 0) throw new Error('no frame times');
  const rows = Math.ceil(times.length / cols);
  const inputs = times.flatMap((t) => ['-ss', t.toFixed(3), '-i', input]);
  const chains = times.map((_, i) => `[${i}:v]trim=end_frame=1,setpts=PTS-STARTPTS,scale=${tileWidth}:-2,setsar=1[f${i}]`);
  const tile = `${times.map((_, i) => `[f${i}]`).join('')}concat=n=${times.length}:v=1:a=0,tile=${cols}x${rows}[out]`;
  return ['-hide_banner', '-nostdin', '-y', ...inputs, '-filter_complex', [...chains, tile].join(';'), '-map', '[out]', '-frames:v', '1', '-q:v', '4', '-loglevel', 'error', output];
}
