import type { Cut, TimeRange } from '@madi/shared';

export interface SilenceOptions {
  /** 이 dB 아래를 무음으로 본다 */
  noiseDb?: number;
  /** 이 길이(초) 이상 이어져야 무음 구간 */
  minSec?: number;
}

export const SILENCE_DEFAULTS = { noiseDb: -35, minSec: 0.7 };

/** 오디오만 훑어서 stderr 로 silence_start / silence_end 를 낸다. */
export function silenceDetectArgs(input: string, opts: SilenceOptions = {}): string[] {
  const { noiseDb, minSec } = { ...SILENCE_DEFAULTS, ...opts };
  return ['-hide_banner', '-nostdin', '-i', input, '-vn', '-af', `silencedetect=noise=${noiseDb}dB:d=${minSec}`, '-f', 'null', '-'];
}

/** silencedetect 출력 → 무음 구간 목록. 끝나지 않은 구간은 durationSec 까지. */
export function parseSilences(stderr: string, durationSec: number): TimeRange[] {
  const out: TimeRange[] = [];
  let open: number | null = null;
  for (const line of stderr.split('\n')) {
    const s = /silence_start:\s*(-?[\d.]+)/.exec(line);
    if (s) {
      open = Math.max(0, Number(s[1]));
      continue;
    }
    const e = /silence_end:\s*(-?[\d.]+)/.exec(line);
    if (e && open !== null) {
      const end = Number(e[1]);
      if (end > open) out.push({ start: open, end });
      open = null;
    }
  }
  if (open !== null && durationSec > open) out.push({ start: open, end: durationSec });
  return out;
}

/**
 * 무음 구간 → 잘라낼 컷. 말 앞뒤 숨은 남긴다(padSec).
 * 영상 맨 앞·뒤 무음도 잘라내되, 아주 짧게 남는 건 버린다.
 */
export function silencesToCuts(silences: TimeRange[], durationSec: number, padSec = 0.2): Cut[] {
  const cuts: Cut[] = [];
  for (const s of silences) {
    const atStart = s.start <= 0.05;
    const atEnd = s.end >= durationSec - 0.05;
    const start = atStart ? 0 : s.start + padSec;
    const end = atEnd ? durationSec : s.end - padSec;
    if (end - start >= 0.3) cuts.push({ start, end, reason: 'silence' });
  }
  return cuts;
}
