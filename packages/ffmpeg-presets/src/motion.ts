import type { TimeRange } from '@madi/shared';
import { escapeFilterPath } from './render.js';

/**
 * 움직임 재기 — 기획안 §5.1 "동작 시범 중의 침묵은 말이 없다는 이유만으로 지우면 안 된다".
 *
 * 화면을 작게 줄여 초당 몇 장만 보고, 앞 장과의 밝기 차이(signalstats YDIF)를 시각별로 남긴다.
 * 이 숫자는 절대값으로 쓰지 않는다: 카메라 · 조명 · 화질에 따라 바닥값이 다르다.
 * 대신 **말하는 동안**의 움직임과 **침묵 동안**의 움직임을 견준다 — 사람이 말을 멈추고 동작을 보여 주면
 * 침묵 구간이 말하던 구간보다 확실히 더 움직인다. 그런 침묵은 자르지 않는다.
 */

export interface MotionSample {
  /** 초 */
  t: number;
  /** 앞 장과의 평균 밝기 차이 (0..255). 클수록 많이 움직였다. */
  diff: number;
}

export const MOTION_DEFAULTS = {
  /** 초당 몇 장 볼지. 4 면 0.25초 간격 — 느린 동작도 한 칸 사이에 티가 난다. */
  fps: 4,
  /** 줄인 너비. 160 이면 25분 영상도 몇십 초. */
  width: 160,
  /** 침묵의 움직임이 말하던 때의 이 배수 이상이어야 "동작 중"으로 본다 */
  ratio: 1.4,
  /** 그래도 이보다는 움직여야 한다 (아주 정적인 영상에서 노이즈로 오판하지 않게) */
  floor: 2,
  /** 침묵 앞뒤 이만큼은 재지 않는다 (말이 끝나는 · 시작하는 움직임) */
  edgeSec: 0.25,
} as const;

/** 소리 없이 화면만 훑어 stderr 로 시각과 YDIF 를 낸다. */
export function motionDetectArgs(input: string, opts: { fps?: number; width?: number } = {}): string[] {
  const fps = opts.fps ?? MOTION_DEFAULTS.fps;
  const width = opts.width ?? MOTION_DEFAULTS.width;
  return ['-hide_banner', '-nostdin', '-i', input, '-an', '-vf', `fps=${fps},scale=${width}:-2,signalstats,metadata=print:key=lavfi.signalstats.YDIF`, '-f', 'null', '-'];
}

/** metadata=print 출력 → 시각별 움직임. 첫 장(앞 장이 없어 0)은 뺀다. */
export function parseMotion(stderr: string): MotionSample[] {
  const out: MotionSample[] = [];
  let t: number | null = null;
  for (const line of stderr.split('\n')) {
    const pts = /pts_time:\s*(-?[\d.]+)/.exec(line);
    if (pts) {
      t = Number(pts[1]);
      continue;
    }
    const y = /lavfi\.signalstats\.YDIF=([\d.]+)/.exec(line);
    if (y && t !== null) {
      const diff = Number(y[1]);
      if (Number.isFinite(t) && Number.isFinite(diff) && t > 0) out.push({ t, diff });
      t = null;
    }
  }
  return out;
}

function mean(xs: number[]): number | null {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
}

function median(xs: number[]): number | null {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/** 구간 안의 평균 움직임. 표본이 없으면 null. */
export function motionLevel(samples: MotionSample[], range: TimeRange): number | null {
  return mean(samples.filter((s) => s.t >= range.start && s.t <= range.end).map((s) => s.diff));
}

export interface SplitByMotion {
  /** 잘라도 되는 침묵 (가만히 있었다) */
  cut: TimeRange[];
  /** 남겨야 하는 침묵 (말은 없지만 동작이 이어진다) */
  kept: TimeRange[];
  /** 말하던 동안의 움직임 중간값 (디버그 · 로그용) */
  speechLevel: number | null;
}

/**
 * 무음 구간을 둘로 나눈다: 말하던 때보다 확실히 더 움직인 침묵은 kept, 나머지는 cut.
 * 움직임 표본이 없거나(화면 없음) 말하던 구간이 없으면 전부 cut — 전과 같은 동작.
 */
export function splitSilencesByMotion(
  silences: TimeRange[],
  samples: MotionSample[],
  durationSec: number,
  opts: { ratio?: number; floor?: number; edgeSec?: number } = {},
): SplitByMotion {
  const ratio = opts.ratio ?? MOTION_DEFAULTS.ratio;
  const floor = opts.floor ?? MOTION_DEFAULTS.floor;
  const edge = opts.edgeSec ?? MOTION_DEFAULTS.edgeSec;
  const inSilence = (t: number) => silences.some((s) => t >= s.start && t <= s.end);
  const speech = samples.filter((s) => s.t <= durationSec && !inSilence(s.t)).map((s) => s.diff);
  const speechLevel = median(speech);
  if (speechLevel === null || samples.length === 0) return { cut: silences, kept: [], speechLevel };
  const bar = Math.max(floor, speechLevel * ratio);
  const cut: TimeRange[] = [];
  const kept: TimeRange[] = [];
  for (const s of silences) {
    const inner = s.end - s.start > edge * 2 + 0.2 ? { start: s.start + edge, end: s.end - edge } : s;
    const level = motionLevel(samples, inner);
    if (level !== null && level >= bar) kept.push(s);
    else cut.push(s);
  }
  return { cut, kept, speechLevel };
}

// ---- 화면의 어느 쪽이 움직이는지 (기획안 §5.4 세로 구도 · §5.5 자막 위치) ----

/** 화면 일부 (비율 0..1). */
export interface MotionRegion {
  name: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * 가로 원본이면 세로로 잘랐을 때 잡을 수 있는 왼쪽 · 가운데 · 오른쪽 기둥을 위 · 아래 띠로 나눠 여섯 조각,
 * 세로 원본이면 위 · 아래 띠 둘. 위 띠는 화면 위 38%, 아래 띠는 아래 38% (자막이 놓이는 곳).
 */
export function regionsFor(width: number, height: number): MotionRegion[] {
  const bands: [string, number, number][] = [
    ['top', 0, 0.38],
    ['bottom', 0.62, 0.38],
  ];
  if (width <= height) return bands.map(([b, y, h]) => ({ name: b, x: 0, y, w: 1, h }));
  // 9:16 창의 너비 (원본 너비 대비). 그보다 좁으면 세 기둥이 겹치니 1/3 로 맞춘다.
  const win = Math.min(1 / 3, (height * 9) / 16 / width);
  const cols: [string, number][] = [
    ['left', 0],
    ['center', 0.5 - win / 2],
    ['right', 1 - win],
  ];
  const out: MotionRegion[] = [];
  for (const [c, x] of cols) for (const [b, y, h] of bands) out.push({ name: `${c}.${b}`, x, y, w: win, h });
  return out;
}

/** 조각마다 움직임을 재서 파일 하나씩에 쓴다 (metadata=print:file). 한 번 훑는다. */
export function motionRegionsArgs(input: string, regions: MotionRegion[], files: string[], opts: { fps?: number; width?: number } = {}): string[] {
  if (regions.length !== files.length || regions.length === 0) throw new Error('regions/files mismatch');
  const fps = opts.fps ?? MOTION_DEFAULTS.fps;
  const width = opts.width ?? MOTION_DEFAULTS.width;
  const n = regions.length;
  const split = `[0:v]fps=${fps},scale=${width}:-2,split=${n}${regions.map((_, i) => `[s${i}]`).join('')}`;
  const chains = regions.map((r, i) => {
    const crop = `crop=w=2*floor(iw*${r.w.toFixed(4)}/2):h=2*floor(ih*${r.h.toFixed(4)}/2):x=2*floor(iw*${r.x.toFixed(4)}/2):y=2*floor(ih*${r.y.toFixed(4)}/2)`;
    return `[s${i}]${crop},signalstats,metadata=print:key=lavfi.signalstats.YDIF:file='${escapeFilterPath(files[i]!)}'[o${i}]`;
  });
  const maps = regions.flatMap((_, i) => ['-map', `[o${i}]`, '-f', 'null', '-']);
  return ['-hide_banner', '-nostdin', '-i', input, '-an', '-filter_complex', [split, ...chains].join(';'), ...maps];
}

/** 여러 구간에 걸친 평균 움직임 (구간 밖 표본은 뺀다). 표본이 없으면 null. */
export function motionLevelIn(samples: MotionSample[], ranges: TimeRange[]): number | null {
  return mean(samples.filter((s) => ranges.some((r) => s.t >= r.start && s.t <= r.end)).map((s) => s.diff));
}

export const FOCUS_DEFAULTS = {
  /** 한 기둥이 다른 기둥보다 이 배수 이상 움직여야 그쪽으로 옮긴다 */
  ratio: 1.3,
  /** 그래도 이보다는 움직여야 한다 */
  floor: 1.5,
} as const;

/**
 * 왼쪽 · 가운데 · 오른쪽 기둥의 움직임 → 세로 크롭 초점 (0 · 0.5 · 1).
 * 확실히 더 움직이는 기둥이 있을 때만 옮기고, 애매하면 가운데 (전과 같다).
 */
export function chooseCropFocus(levels: { left: number | null; center: number | null; right: number | null }, opts: { ratio?: number; floor?: number } = {}): number {
  const ratio = opts.ratio ?? FOCUS_DEFAULTS.ratio;
  const floor = opts.floor ?? FOCUS_DEFAULTS.floor;
  const cands: [number, number][] = [
    [0, levels.left ?? 0],
    [0.5, levels.center ?? 0],
    [1, levels.right ?? 0],
  ];
  const sorted = [...cands].sort((a, b) => b[1] - a[1]);
  const [best, second] = [sorted[0]!, sorted[1]!];
  if (best[0] === 0.5) return 0.5;
  if (best[1] >= floor && best[1] >= second[1] * ratio) return best[0];
  return 0.5;
}

/**
 * 위 · 아래 띠의 움직임 → 자막을 어디 둘지. 아래가 확실히 더 움직이면(다리 · 골반 동작) 위로.
 * 자막은 보통 아래에 있으니 아래가 기본이다.
 */
export function chooseSubtitleSide(levels: { top: number | null; bottom: number | null }, opts: { ratio?: number; floor?: number } = {}): 'bottom' | 'top' {
  const ratio = opts.ratio ?? 1.5;
  const floor = opts.floor ?? FOCUS_DEFAULTS.floor;
  const top = levels.top ?? 0;
  const bottom = levels.bottom ?? 0;
  return bottom >= floor && bottom >= top * ratio ? 'top' : 'bottom';
}

/** 자막을 위에 둘 때의 아래 여백 (화면 높이 비율). 맨 위 앱 UI 아래로. */
export const SUBTITLE_TOP_MARGIN = 0.7;
