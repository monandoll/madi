import { nanoid } from 'nanoid';
import type { Segment } from '@madi/shared';

/** 에이전트(set_subtitle_text)나 사용자가 직접 준 자막 줄. */
export interface SubtitleLine {
  start: number;
  end: number;
  text: string;
}

/**
 * 자막 문장 고치기 (순수 함수).
 * - replaceAll 이거나 기존 자막이 없으면 준 줄들이 자막 전체가 된다.
 * - 아니면 각 줄과 절반 넘게 겹치는 기존 문장을 빼고 그 자리에 넣는다. 나머지는 그대로.
 * 시각이 뒤집힌 줄은 바로잡고, 빈 글은 버린다. 단어 시각(words)은 새 줄엔 없다.
 */
export function mergeSubtitleLines(existing: Segment[], lines: SubtitleLine[], replaceAll = false): Segment[] {
  const clean = lines
    .map((l) => ({ start: Math.max(0, Math.min(l.start, l.end)), end: Math.max(l.start, l.end), text: l.text.replace(/\s+/g, ' ').trim() }))
    .filter((l) => l.text.length > 0)
    .map((l) => (l.end - l.start < 0.3 ? { ...l, end: l.start + 0.3 } : l))
    .sort((a, b) => a.start - b.start);
  const fresh: Segment[] = clean.map((l) => ({ id: nanoid(8), start: l.start, end: l.end, text: l.text, words: [] }));
  if (replaceAll || existing.length === 0) return fresh;
  const kept = existing.filter((s) => !clean.some((l) => overlapsMostly(s, l)));
  return [...kept, ...fresh].sort((a, b) => a.start - b.start);
}

function overlapsMostly(s: Segment, l: SubtitleLine): boolean {
  const o = Math.min(s.end, l.end) - Math.max(s.start, l.start);
  if (o <= 0) return false;
  const len = Math.max(0.01, s.end - s.start);
  return o >= 0.5 * len || o >= 0.5 * Math.max(0.01, l.end - l.start);
}
