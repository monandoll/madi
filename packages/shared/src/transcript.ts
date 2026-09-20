import { z } from 'zod';

/** 단어 하나. 시각은 초. */
export const Word = z.object({
  start: z.number(),
  end: z.number(),
  text: z.string(),
  /** whisper 확신도 0..1 (없으면 null) */
  p: z.number().nullable(),
});
export type Word = z.infer<typeof Word>;

/** 문장 단위. 자막 한 줄이 된다. */
export const Segment = z.object({
  id: z.string(),
  start: z.number(),
  end: z.number(),
  text: z.string(),
  secondaryText: z.string().max(200).optional(),
  words: z.array(Word),
});
export type Segment = z.infer<typeof Segment>;

/** 자막의 불변 버전. 음성 인식 또는 사용자가 직접 지정한 문구. */
export const Transcript = z.object({
  id: z.string(),
  videoId: z.string(),
  language: z.string(),
  model: z.string(),
  segments: z.array(Segment),
  createdAt: z.number().int(),
});
export type Transcript = z.infer<typeof Transcript>;

/** 시각 구간 [start, end) 초 */
export const TimeRange = z.object({ start: z.number().min(0), end: z.number().min(0) });
export type TimeRange = z.infer<typeof TimeRange>;

export const CaptionLine = TimeRange.extend({ text: z.string().trim().min(1).max(200), secondaryText: z.string().trim().max(200).optional() }).refine((s) => s.end > s.start, 'end must follow start');
