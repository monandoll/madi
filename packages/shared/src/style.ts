import { z } from 'zod';
import { SubtitleStyle } from './edit.js';

/**
 * StyleProfile — 사용자의 편집 취향.
 * - 규칙(style.md): 사용자가 쓴 것 + 완성본에서 배운 것(learned 블록, 자동 갱신)
 * - 완성본(reference): 사용자가 예전에 만든 결과물. 폴더를 정하면 엔진이 하나씩 분석한다.
 * - learned: 완성본 통계를 합친 값. 무음 기준·숏폼 길이·컷 빈도의 기본값이 된다.
 */
export const StyleRule = z.object({
  text: z.string(),
  /** 완성본에서 배운 줄. 사용자가 못 지우고, 다시 배우면 갱신된다. */
  learned: z.boolean(),
});
export type StyleRule = z.infer<typeof StyleRule>;

export const Aspect = z.enum(['9:16', '16:9', 'other']);
export type Aspect = z.infer<typeof Aspect>;

/** 원본과 완성본을 자막으로 맞춰 본 결과. */
export const PairDiff = z.object({
  /** 짝이 된 원본 영상 */
  videoId: z.string(),
  /** 완성본에 남은 원본 비율 0..1 */
  keptRatio: z.number().min(0).max(1),
  /** 원본 앞·뒤에서 잘라낸 길이(초) */
  introTrimSec: z.number().min(0),
  outroTrimSec: z.number().min(0),
  /** 중간에서 잘라낸 구간 수 */
  cutCount: z.number().int().min(0),
});
export type PairDiff = z.infer<typeof PairDiff>;

export const ReferenceStats = z.object({
  durationSec: z.number(),
  width: z.number().int(),
  height: z.number().int(),
  hasAudio: z.boolean(),
  aspect: Aspect,
  /** 완성본 안에 남아 있는 무음 구간들 — 가장 긴 것이 "이 정도는 참는다" 기준 */
  silenceCount: z.number().int(),
  maxSilenceSec: z.number(),
  /** 장면 전환 수와 분당 컷 수 */
  sceneCount: z.number().int(),
  cutsPerMin: z.number(),
  pair: PairDiff.nullable(),
});
export type ReferenceStats = z.infer<typeof ReferenceStats>;

export const ReferenceStatus = z.enum(['queued', 'analyzing', 'done', 'failed', 'missing']);
export type ReferenceStatus = z.infer<typeof ReferenceStatus>;

export const Reference = z.object({
  id: z.string(),
  path: z.string(),
  fileName: z.string(),
  title: z.string(),
  sizeBytes: z.number().int(),
  status: ReferenceStatus,
  stats: ReferenceStats.nullable(),
  error: z.string().nullable(),
  createdAt: z.number().int(),
  updatedAt: z.number().int(),
});
export type Reference = z.infer<typeof Reference>;

/** 완성본들을 합쳐 배운 값. */
export const StyleLearned = z.object({
  count: z.number().int().min(1),
  aspect: z.enum(['9:16', '16:9', 'mixed']),
  medianDurationSec: z.number(),
  /** 이 길이(초) 넘는 무음은 잘라내는 걸로 본다 */
  silenceMinSec: z.number(),
  cutsPerMin: z.number(),
  /** 짝을 맞춘 원본이 있을 때만 */
  keptRatio: z.number().nullable(),
  introTrimSec: z.number().nullable(),
  learnedAt: z.number().int(),
});
export type StyleLearned = z.infer<typeof StyleLearned>;

export const StyleResponse = z.object({
  rules: z.array(StyleRule),
  learned: StyleLearned.nullable(),
  references: z.array(Reference),
  subtitleStyle: SubtitleStyle,
  /** 무음 잘라내기 기준(초). 배운 값이 있으면 그것. */
  silenceMinSec: z.number(),
});
export type StyleResponse = z.infer<typeof StyleResponse>;

export const AddRuleRequest = z.object({ rule: z.string().trim().min(2).max(200) });
export type AddRuleRequest = z.infer<typeof AddRuleRequest>;
