import type { Chapter, Segment, TimeRange } from '@madi/shared';

/** 순수 함수: 자막 문장 + 무음 + 장면 전환 → 챕터. 파일·DB 를 모른다. */

export interface SplitOptions {
  /** 이보다 짧은 챕터는 만들지 않는다 */
  minSec?: number;
  /** 이쯤 되면 약한 경계에서도 자른다 */
  targetSec?: number;
  /** 이보다 길어지면 가장 좋은 경계에서 무조건 자른다 */
  maxSec?: number;
}

export const SPLIT_DEFAULTS: Required<SplitOptions> = { minSec: 45, targetSec: 180, maxSec: 420 };

interface Boundary {
  at: number;
  score: number;
}

const r1 = (n: number) => Math.round(n * 10) / 10;

/**
 * 자막을 믿고 쓸 수 있는지: 문장이 둘 이상이고 말한 시간이 전체의 15% 는 넘어야 한다.
 * (음악·소음만 있는 영상에서 whisper 가 지어낸 몇 줄로 챕터를 나누지 않게)
 */
export function transcriptUsable(segments: Segment[], durationSec: number): boolean {
  if (segments.length < 2 || durationSec <= 0) return false;
  const speech = segments.reduce((a, s) => a + Math.max(0, s.end - s.start), 0);
  return speech / durationSec >= 0.15;
}

/**
 * 경계 후보 점수: 문장 사이 쉼(초, 최대 4) + 장면 전환이 ±6초 안에 있으면 +2 + 무음 1.5초 이상이면 +1.
 * 자막이 없거나 못 믿으면 장면 전환마다 후보 (점수 3 = 강한 경계).
 */
export function candidateBoundaries(segments: Segment[], silences: TimeRange[], scenes: number[], durationSec = Number.POSITIVE_INFINITY): Boundary[] {
  const out: Boundary[] = [];
  const nearScene = (t: number) => scenes.some((s) => Math.abs(s - t) <= 6);
  const silenceAt = (t: number) => silences.find((s) => t >= s.start - 0.3 && t <= s.end + 0.3);
  const usable = Number.isFinite(durationSec) ? transcriptUsable(segments, durationSec) : segments.length >= 2;
  if (usable) {
    for (let i = 1; i < segments.length; i++) {
      const prev = segments[i - 1]!;
      const cur = segments[i]!;
      const gap = Math.max(0, cur.start - prev.end);
      if (gap < 0.6) continue;
      const mid = prev.end + gap / 2;
      let score = Math.min(gap, 4);
      if (nearScene(mid)) score += 2;
      const sil = silenceAt(mid);
      if (sil && sil.end - sil.start >= 1.5) score += 1;
      out.push({ at: r1(cur.start), score: r1(score) });
    }
    return out;
  }
  return scenes.map((s) => ({ at: r1(s), score: 3 }));
}

/**
 * 챕터 나누기. 앞에서부터 걸어가며:
 * - 길이 < min: 안 자른다
 * - 길이 ≥ max: 지금까지 본 가장 좋은 경계에서 자른다
 * - 강한 경계(점수 ≥ 3): 자른다
 * - 길이 ≥ target 이고 경계 점수 ≥ 1.5: 자른다
 * 마지막 챕터가 min 보다 짧으면 앞 챕터에 붙인다.
 */
export function splitChapters(
  input: { segments: Segment[]; silences: TimeRange[]; scenes: number[]; durationSec: number },
  opts: SplitOptions = {},
): Chapter[] {
  const o = { ...SPLIT_DEFAULTS, ...opts };
  const { durationSec } = input;
  if (durationSec <= 0) return [];
  const usable = transcriptUsable(input.segments, durationSec);
  const segments = usable ? input.segments : [];
  const cands = candidateBoundaries(segments, input.silences, input.scenes, durationSec).filter((c) => c.at > 0 && c.at < durationSec);
  const cuts: number[] = [];
  let start = 0;
  let seen: Boundary[] = [];
  for (const c of cands) {
    const len = c.at - start;
    if (len < o.minSec) continue;
    seen.push(c);
    let cutAt: number | null = null;
    if (len >= o.maxSec) {
      // 너무 길어졌다: target 을 넘긴 뒤의 후보 중 가장 좋은 곳(같으면 뒤쪽)에서 자른다
      const late = seen.filter((b) => b.at - start >= o.targetSec);
      const pool = late.length ? late : seen;
      cutAt = pool.reduce((a, b) => (b.score >= a.score ? b : a)).at;
    } else if (c.score >= 3) cutAt = c.at;
    else if (len >= o.targetSec && c.score >= 1.5) cutAt = c.at;
    if (cutAt !== null) {
      cuts.push(cutAt);
      start = cutAt;
      seen = [];
    }
  }
  // 마지막 조각이 너무 짧으면 앞에 붙인다
  if (cuts.length && durationSec - cuts[cuts.length - 1]! < o.minSec) cuts.pop();
  const bounds = [0, ...cuts, durationSec];
  const chapters: Chapter[] = [];
  for (let i = 0; i < bounds.length - 1; i++) {
    const s = bounds[i]!;
    const e = bounds[i + 1]!;
    const inside = segments.filter((seg) => seg.start >= s - 0.2 && seg.start < e);
    chapters.push({
      index: i,
      title: chapterTitle(inside, i),
      start: r1(s),
      end: r1(e),
      highlight: pickHighlight(inside, { start: s, end: e }),
    });
  }
  return chapters;
}

/** 첫 문장을 24자 안으로. 자막이 없으면 "1부". */
export function chapterTitle(segments: Segment[], index: number): string {
  const first = segments.find((s) => s.text.trim().length > 0);
  if (!first) return `${index + 1}부`;
  const text = first.text.trim().replace(/\s+/g, ' ');
  return text.length > 24 ? `${text.slice(0, 23).trimEnd()}…` : text;
}

export interface HighlightOptions {
  minSec?: number;
  targetSec?: number;
  maxSec?: number;
}
export const HIGHLIGHT_DEFAULTS: Required<HighlightOptions> = { minSec: 15, targetSec: 40, maxSec: 60 };

/**
 * 챕터 안에서 숏폼 구간 하나. 챕터가 max 이하면 통째로.
 * 아니면 문장 시작점마다 target 길이 창을 놓고, 문장 경계에 맞춰 끝을 당긴 뒤 말이 가장 많은 창을 고른다.
 * 자막이 없으면 챕터 앞부분 target 초.
 */
export function pickHighlight(segments: Segment[], range: TimeRange, opts: HighlightOptions = {}): TimeRange | null {
  const o = { ...HIGHLIGHT_DEFAULTS, ...opts };
  const len = range.end - range.start;
  if (len < o.minSec) return null;
  if (len <= o.maxSec) return { start: r1(range.start), end: r1(range.end) };
  const segs = segments.filter((s) => s.start >= range.start - 0.2 && s.end <= range.end + 0.2);
  if (segs.length === 0) return { start: r1(range.start), end: r1(Math.min(range.end, range.start + o.targetSec)) };
  let bestScore = -1;
  let best: TimeRange | null = null;
  for (let i = 0; i < segs.length; i++) {
    const start = segs[i]!.start;
    let end = start;
    let words = 0;
    for (let j = i; j < segs.length && segs[j]!.end - start <= o.targetSec; j++) {
      end = segs[j]!.end;
      words += segs[j]!.words.length || segs[j]!.text.split(/\s+/).filter(Boolean).length;
    }
    if (end - start < o.minSec) continue;
    const score = words; // 말이 많은 창. 같으면 앞쪽
    if (score > bestScore) {
      bestScore = score;
      best = { start: r1(Math.max(range.start, start - 0.3)), end: r1(Math.min(range.end, end + 0.3)) };
    }
  }
  return best ?? { start: r1(range.start), end: r1(Math.min(range.end, range.start + o.targetSec)) };
}

/** 자동 숏폼: 하이라이트가 있는 챕터에서 순서대로 max 개. */
export function pickShorts(chapters: Chapter[], max: number): { title: string; range: TimeRange }[] {
  return chapters
    .filter((c) => c.highlight)
    .slice(0, Math.max(0, max))
    .map((c) => ({ title: c.title, range: c.highlight! }));
}
