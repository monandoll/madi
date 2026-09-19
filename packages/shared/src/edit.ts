import { z } from 'zod';
import { TimeRange } from './transcript.js';

/** 잘라낼 구간과 이유. */
export const Cut = TimeRange.extend({
  reason: z.enum(['silence', 'manual', 'ai']),
});
export type Cut = z.infer<typeof Cut>;

export const Crop = z.enum(['none', 'vertical']);
export type Crop = z.infer<typeof Crop>;

/** 프리뷰 자막 박스: 노란 배경에 진한 글자 (디자인 토큰 subtitle / text). */
export const SubtitleStyle = z.object({
  fontFamily: z.string(),
  fontSize: z.number().int().min(8).max(200),
  color: z.string(),
  boxColor: z.string(),
  /** 화면 아래에서 띄우는 비율 0..1 */
  bottom: z.number().min(0).max(1),
  /** 강조한 단어의 색 (기획안 §6 예시 2 — "견갑골 설명에만 단어를 강조") */
  emphasisColor: z.string().default('#3E6B8A'),
});
export type SubtitleStyle = z.infer<typeof SubtitleStyle>;

export const DEFAULT_SUBTITLE_STYLE: SubtitleStyle = {
  fontFamily: 'Pretendard',
  fontSize: 56,
  color: '#2B2622',
  boxColor: '#E8C33F',
  // 9:16 은 화면 아래에 앱 UI(더보기 · 프로필 · 음원)가 겹친다. 그 위로 올린다.
  bottom: 0.18,
  // 노란 박스 위의 진한 파랑 (accent). 굵기 · 크기로도 띄운다.
  emphasisColor: '#3E6B8A',
};

/**
 * 자막에서 강조할 단어. start · end(원본 초)를 주면 그 구간에서만 — "견갑골 설명에만" (기획안 §6 예시 2).
 * 없으면 영상 전체에서 그 단어가 나올 때마다.
 */
export const Emphasis = z.object({
  term: z.string().trim().min(1).max(40),
  start: z.number().min(0).nullable().default(null),
  end: z.number().min(0).nullable().default(null),
});
export type Emphasis = z.infer<typeof Emphasis>;

/** 이 원본 구간(단어 · 문장)에 걸리는 강조 단어들. */
export function emphasisTerms(emphasis: Emphasis[], at: TimeRange): string[] {
  const mid = (at.start + at.end) / 2;
  return emphasis.filter((e) => (e.start === null || mid >= e.start) && (e.end === null || mid <= e.end)).map((e) => e.term);
}

/** 글을 강조 조각과 아닌 조각으로 나눈다. 렌더(ASS 태그)와 화면(굵은 글씨)이 같이 쓴다. 긴 단어부터 맞춘다. */
export function splitEmphasis(text: string, terms: string[]): { text: string; strong: boolean }[] {
  const ts = [...new Set(terms.map((t) => t.trim()).filter(Boolean))].sort((a, b) => b.length - a.length);
  if (!ts.length || !text) return text ? [{ text, strong: false }] : [];
  const out: { text: string; strong: boolean }[] = [];
  let i = 0;
  while (i < text.length) {
    const hit = ts.find((t) => text.startsWith(t, i));
    if (hit) {
      out.push({ text: hit, strong: true });
      i += hit.length;
      continue;
    }
    const last = out[out.length - 1];
    if (last && !last.strong) last.text += text[i]!;
    else out.push({ text: text[i]!, strong: false });
    i += 1;
  }
  return out;
}

/**
 * 세로(9:16) 크롭의 가로 초점 0..1 (0 왼쪽 끝, 0.5 가운데, 1 오른쪽 끝). null 이면 렌더할 때 움직임을 보고 고른다 (기획안 §5.4).
 * 고른 값은 Edit 에 다시 적힌다 — 렌더는 항상 Edit 로부터 재현 가능해야 하니까.
 */
export const CropFocus = z.number().min(0).max(1);

/**
 * 편집 결정 목록. 렌더는 항상 이것으로부터 재현 가능해야 한다.
 * - keep: 이 구간만 쓴다 (숏폼). null 이면 전체.
 * - parts: 순서대로 이어 붙일 조각들. 비어 있지 않으면 keep 대신 쓴다 — "동작을 먼저 보여 주고 설명을 뒤에" 같은 구성 (기획안 §4).
 * - cuts: keep(또는 parts) 안에서 빼는 구간들.
 * - crop: 세로(9:16) 변환. cropFocus 는 그때 어디를 잡을지.
 * - subtitles: 자막 번인 여부 (transcriptId 의 문장을 쓴다). subtitleAuto 면 렌더할 때 동작을 가리지 않는 쪽(아래/위)을 고른다 (기획안 §5.5).
 */
export const Edit = z.object({
  id: z.string(),
  videoId: z.string(),
  title: z.string(),
  keep: TimeRange.nullable(),
  parts: z.array(TimeRange).default([]),
  cuts: z.array(Cut),
  crop: Crop,
  cropFocus: CropFocus.nullable().default(null),
  subtitles: z.boolean(),
  transcriptId: z.string().nullable(),
  subtitleStyle: SubtitleStyle,
  subtitleAuto: z.boolean().default(true),
  /** 강조할 단어들 (자막 번인에서 굵게 · 다른 색). */
  emphasis: z.array(Emphasis).default([]),
  /**
   * 어느 Edit 를 고쳐서 만든 것인지 (기획안 §6 "수정안 비교"). 결과물이 이미 있는 Edit 는 제자리에서 고치지 않고
   * 새 Edit 를 만든다 — 이전 결과물도 계속 자기 Edit 로부터 재현돼야 하니까.
   */
  revisionOf: z.string().nullable().default(null),
  /** 아직 안 씀. 구간별 배속. */
  speed: z.array(TimeRange.extend({ rate: z.number().positive() })),
  createdAt: z.number().int(),
});
export type Edit = z.infer<typeof Edit>;

/**
 * 남는 구간들 = keep(또는 parts 각각)에서 cuts 를 뺀 것, **주어진 순서대로**. 렌더와 자막 시각 재배치가 같이 쓴다.
 * parts 가 있으면 원본 순서와 다를 수 있다 (시범을 먼저, 설명을 뒤에).
 */
export function keepSegments(edit: Pick<Edit, 'keep' | 'cuts'> & { parts?: TimeRange[] | undefined }, durationSec: number): TimeRange[] {
  const bases: TimeRange[] = edit.parts && edit.parts.length ? edit.parts : [edit.keep ?? { start: 0, end: durationSec }];
  const out: TimeRange[] = [];
  for (const base of bases) {
    const start = Math.max(0, base.start);
    const end = Math.min(durationSec, base.end);
    if (end <= start) continue;
    const cuts = [...edit.cuts]
      .map((c) => ({ start: Math.max(start, c.start), end: Math.min(end, c.end) }))
      .filter((c) => c.end > c.start)
      .sort((a, b) => a.start - b.start);
    let cursor = start;
    for (const c of cuts) {
      if (c.start > cursor) out.push({ start: cursor, end: c.start });
      cursor = Math.max(cursor, c.end);
    }
    if (cursor < end) out.push({ start: cursor, end });
  }
  return out.filter((r) => r.end - r.start > 0.01);
}

/** 원본 시각 → 렌더 결과 시각. 잘린 구간 안이면 null. 구간 순서가 원본과 달라도(parts) 된다. */
export function remapTime(t: number, segments: TimeRange[]): number | null {
  let acc = 0;
  for (const s of segments) {
    if (t >= s.start && t <= s.end) return acc + (t - s.start);
    acc += s.end - s.start;
  }
  return null;
}

/**
 * 원본 구간(단어 등) → 결과물 구간. 구간의 가운데가 남는 구간 안에 있어야 살아남고,
 * 남는 구간 경계에 걸치면 그만큼 잘린다. 경계에 정확히 닿는 단어가 양쪽에 다 들어가지 않게 반개구간으로 본다.
 */
export function remapRange(range: TimeRange, segments: TimeRange[]): TimeRange | null {
  const mid = (range.start + range.end) / 2;
  let acc = 0;
  for (const s of segments) {
    if (mid >= s.start && mid < s.end) {
      const start = acc + Math.max(range.start, s.start) - s.start;
      const end = acc + Math.min(range.end, s.end) - s.start;
      return end > start ? { start, end } : null;
    }
    acc += s.end - s.start;
  }
  return null;
}

export function totalDuration(segments: TimeRange[]): number {
  return segments.reduce((a, s) => a + (s.end - s.start), 0);
}

/** 두 편집 결정의 차이 — 결과물 화면의 "이전과 달라진 점" 과 에이전트 도구 결과가 같이 쓴다. */
export interface EditDiff {
  keep?: { from: TimeRange | null; to: TimeRange | null };
  parts?: { from: TimeRange[]; to: TimeRange[] };
  cuts: { added: TimeRange[]; removed: TimeRange[] };
  crop?: { from: Crop; to: Crop };
  cropFocus?: { from: number | null; to: number | null };
  subtitles?: { from: boolean; to: boolean };
  /** 자막 아래 여백 (커지면 위로 간 것) */
  subtitleBottom?: { from: number; to: number };
  emphasis?: { added: string[]; removed: string[] };
  /** 하나라도 달라졌는지 */
  changed: boolean;
}

type Diffable = Pick<Edit, 'keep' | 'parts' | 'cuts' | 'crop' | 'cropFocus' | 'subtitles' | 'subtitleStyle' | 'emphasis'>;

const sameRange = (a: TimeRange | null, b: TimeRange | null) => (a === null || b === null ? a === b : Math.abs(a.start - b.start) < 0.05 && Math.abs(a.end - b.end) < 0.05);
const sameRanges = (a: TimeRange[], b: TimeRange[]) => a.length === b.length && a.every((r, i) => sameRange(r, b[i]!));

export function editDiff(prev: Diffable, next: Diffable): EditDiff {
  const d: EditDiff = { cuts: { added: [], removed: [] }, changed: false };
  if (!sameRange(prev.keep, next.keep)) d.keep = { from: prev.keep, to: next.keep };
  if (!sameRanges(prev.parts, next.parts)) d.parts = { from: prev.parts, to: next.parts };
  d.cuts.added = next.cuts.filter((c) => !prev.cuts.some((p) => sameRange(p, c))).map(({ start, end }) => ({ start, end }));
  d.cuts.removed = prev.cuts.filter((c) => !next.cuts.some((n) => sameRange(n, c))).map(({ start, end }) => ({ start, end }));
  if (prev.crop !== next.crop) d.crop = { from: prev.crop, to: next.crop };
  if (next.crop === 'vertical' && prev.cropFocus !== next.cropFocus) d.cropFocus = { from: prev.cropFocus, to: next.cropFocus };
  if (prev.subtitles !== next.subtitles) d.subtitles = { from: prev.subtitles, to: next.subtitles };
  if (next.subtitles && Math.abs(prev.subtitleStyle.bottom - next.subtitleStyle.bottom) > 0.01) d.subtitleBottom = { from: prev.subtitleStyle.bottom, to: next.subtitleStyle.bottom };
  const pe = new Set(prev.emphasis.map((e) => e.term));
  const ne = new Set(next.emphasis.map((e) => e.term));
  const added = [...ne].filter((t) => !pe.has(t));
  const removed = [...pe].filter((t) => !ne.has(t));
  if (added.length || removed.length) d.emphasis = { added, removed };
  d.changed = !!(d.keep || d.parts || d.cuts.added.length || d.cuts.removed.length || d.crop || d.cropFocus || d.subtitles || d.subtitleBottom || d.emphasis);
  return d;
}
