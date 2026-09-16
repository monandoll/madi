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
});
export type SubtitleStyle = z.infer<typeof SubtitleStyle>;

export const DEFAULT_SUBTITLE_STYLE: SubtitleStyle = {
  fontFamily: 'Pretendard Variable',
  fontSize: 56,
  color: '#2B2622',
  boxColor: '#E8C33F',
  bottom: 0.14,
};

/**
 * 편집 결정 목록. 렌더는 항상 이것으로부터 재현 가능해야 한다.
 * - keep: 이 구간만 쓴다 (숏폼). null 이면 전체.
 * - cuts: keep 안에서 빼는 구간들.
 * - crop: 세로(9:16) 변환.
 * - subtitles: 자막 번인 여부 (transcriptId 의 문장을 쓴다).
 */
export const Edit = z.object({
  id: z.string(),
  videoId: z.string(),
  title: z.string(),
  keep: TimeRange.nullable(),
  cuts: z.array(Cut),
  crop: Crop,
  subtitles: z.boolean(),
  transcriptId: z.string().nullable(),
  subtitleStyle: SubtitleStyle,
  /** 아직 안 씀. 구간별 배속. */
  speed: z.array(TimeRange.extend({ rate: z.number().positive() })),
  createdAt: z.number().int(),
});
export type Edit = z.infer<typeof Edit>;

/** 남는 구간들 = keep 에서 cuts 를 뺀 것. 렌더와 자막 시각 재배치가 같이 쓴다. */
export function keepSegments(edit: Pick<Edit, 'keep' | 'cuts'>, durationSec: number): TimeRange[] {
  const base: TimeRange = edit.keep ?? { start: 0, end: durationSec };
  const start = Math.max(0, base.start);
  const end = Math.min(durationSec, base.end);
  if (end <= start) return [];
  const cuts = [...edit.cuts]
    .map((c) => ({ start: Math.max(start, c.start), end: Math.min(end, c.end) }))
    .filter((c) => c.end > c.start)
    .sort((a, b) => a.start - b.start);
  const out: TimeRange[] = [];
  let cursor = start;
  for (const c of cuts) {
    if (c.start > cursor) out.push({ start: cursor, end: c.start });
    cursor = Math.max(cursor, c.end);
  }
  if (cursor < end) out.push({ start: cursor, end });
  return out.filter((r) => r.end - r.start > 0.01);
}

/** 원본 시각 → 렌더 결과 시각. 잘린 구간 안이면 null. */
export function remapTime(t: number, segments: TimeRange[]): number | null {
  let acc = 0;
  for (const s of segments) {
    if (t >= s.start && t <= s.end) return acc + (t - s.start);
    if (t < s.start) return null;
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
