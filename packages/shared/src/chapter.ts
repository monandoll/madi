import { z } from 'zod';

/**
 * 롱폼 챕터 (6단계). 자막 문장 사이 쉼 + 장면 전환 + 무음으로 나눈다. AI 없이도 만든다.
 * 제목은 그 챕터 첫 문장(자막 없으면 "1부, 2부…").
 */
export const Chapter = z.object({
  index: z.number().int().min(0),
  title: z.string(),
  start: z.number().min(0),
  end: z.number().min(0),
  /** 챕터 안에서 숏폼으로 뽑기 좋은 구간 (문장 경계에 맞춘 20~60초) */
  highlight: z.object({ start: z.number().min(0), end: z.number().min(0) }).nullable(),
});
export type Chapter = z.infer<typeof Chapter>;

export const Chapters = z.object({
  videoId: z.string(),
  items: z.array(Chapter),
  /** 자막이 있을 때 만든 것인지 (없으면 장면·무음만) */
  fromTranscript: z.boolean(),
  createdAt: z.number().int(),
});
export type Chapters = z.infer<typeof Chapters>;

/** 이 길이(초)를 넘으면 챕터·숏폼 자동 추출 버튼이 보인다. */
export const LONGFORM_MIN_SEC = 120;
