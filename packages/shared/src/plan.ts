import { z } from 'zod';
import { InsightSectionKind, WhyRange } from './style.js';

/**
 * 편집안 — 촬영본 하나를 AI 가 자막 · 무음 · 움직임 · 장면으로 읽고 남긴 **초안** (기획안 §4 · §13).
 * 완성본의 ReferenceInsight 가 "이 제작자는 이렇게 만든다" 라면, 이건 "이 촬영본은 이렇게 만들자" 다.
 * 파일은 만들지 않는다. 사용자가 보고 골라야 렌더가 걸린다 (§6: AI 초안 → 확인 → 수정 → 확정 → 내보내기).
 */
export const PlanCutKind = z.enum(['repeat', 'ng', 'aside', 'silence', 'other']);
export type PlanCutKind = z.infer<typeof PlanCutKind>;

/** 어느 채널용 후보인지. any 는 어디든. */
export const PlanChannel = z.enum(['reels', 'shorts', 'tiktok', 'any']);
export type PlanChannel = z.infer<typeof PlanChannel>;

export const PlanSection = z.object({
  title: z.string().max(60),
  start: z.number().min(0),
  end: z.number().min(0),
  kind: InsightSectionKind.default('other'),
  /** 이 구간을 어떻게 편집할지 한 줄 (기획안 §4 "편집 초안") */
  note: z.string().max(200).default(''),
});
export type PlanSection = z.infer<typeof PlanSection>;

/**
 * 사용자가 편집안 후보에 남긴 판단 (기획안 §9 — 확정 · 거절 기록이 가장 중요한 학습 데이터).
 * rejected 는 "이건 빼" (편집안대로 만들기에서 빠지고, 에이전트에게 다시 제안하지 말라고 알린다).
 * accepted 는 숏폼 후보를 눌러 실제로 만든 것. index 는 그 목록(cutCandidates · shortCandidates)의 자리.
 */
export const PlanFeedbackKind = z.enum(['cut', 'short']);
export type PlanFeedbackKind = z.infer<typeof PlanFeedbackKind>;
export const PlanVerdict = z.enum(['rejected', 'accepted']);
export type PlanVerdict = z.infer<typeof PlanVerdict>;
export const PlanFeedback = z.object({
  kind: PlanFeedbackKind,
  index: z.number().int().min(0),
  verdict: PlanVerdict,
  at: z.number().int(),
});
export type PlanFeedback = z.infer<typeof PlanFeedback>;

export const EditPlan = z.object({
  videoId: z.string(),
  /** 이 영상이 전하려는 것 */
  purpose: z.string().max(300),
  audience: z.string().max(200).default(''),
  /** 어디서 어떻게 시작할지 */
  hook: z.string().max(200).default(''),
  /** 롱폼 이야기 순서 + 구간별 편집 초안 */
  sections: z.array(PlanSection).default([]),
  /** 지우면 안 되는 구간 — 시범 · 시범 중 침묵 · 주의사항 · 횟수 */
  keepRanges: z.array(WhyRange).default([]),
  /** 반복 설명 · NG · 잡담 후보 (사용자가 확인한 뒤에 잘린다) */
  cutCandidates: z.array(WhyRange.extend({ kind: PlanCutKind.default('other') })).default([]),
  /** 독립된 숏폼 후보 + 이유 + 채널 */
  shortCandidates: z.array(WhyRange.extend({ title: z.string().max(60), channel: PlanChannel.default('any') })).default([]),
  /** 자막이 잘못 적었을 법한 운동 · 해부학 용어 (바른 표기) */
  terms: z.array(z.string().max(40)).default([]),
  tags: z.array(z.string().max(30)).default([]),
  /** 자막을 보고 만든 것인지 (아니면 장면 · 무음만) */
  fromTranscript: z.boolean().default(false),
  /** 사용자가 후보에 남긴 판단. 편집안을 다시 만들면 비워진다 (자리가 바뀌니까). */
  feedback: z.array(PlanFeedback).default([]),
  /** 화면을 보고 안 것 (기획안 §5.4 · §10): 사람이 어느 쪽에 있는지 · 앵글 · 동작이 시작되는 지점. 화면을 안 봤으면 null. */
  framing: z
    .object({
      side: z.enum(['left', 'center', 'right', 'unknown']).default('unknown'),
      note: z.string().max(200).default(''),
    })
    .nullable()
    .default(null),
  /** AI 가 본 화면의 시각들 (§8.1 "분석에 사용한 프레임 정보"). 안 봤으면 빈 목록. */
  frameTimes: z.array(z.number().min(0)).default([]),
  provider: z.enum(['claude', 'codex']),
  createdAt: z.number().int(),
});
export type EditPlan = z.infer<typeof EditPlan>;

/** 그 후보를 사용자가 뺐는지. */
export function planRejected(plan: Pick<EditPlan, 'feedback'>, kind: PlanFeedbackKind, index: number): boolean {
  return plan.feedback.some((f) => f.kind === kind && f.index === index && f.verdict === 'rejected');
}
