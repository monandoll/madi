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

/** 시각 구간 + 이유. 에이전트가 읽고 사람도 읽는다. */
const WhyRange = z.object({
  start: z.number().min(0),
  end: z.number().min(0),
  why: z.string().max(200),
});

export const InsightSectionKind = z.enum(['intro', 'setup', 'demo', 'qa', 'closing', 'other']);
export type InsightSectionKind = z.infer<typeof InsightSectionKind>;

/**
 * 영상별 기억 — 완성본 하나를 AI 가 자막으로 읽고 남긴 메모.
 * 숫자(ReferenceStats)가 아니라 뜻이다: 무슨 영상인지, 어떻게 짜였는지, 어디가 지우면 안 되는 곳인지.
 * 처음 한 번 넉넉히 읽고 저장해 두면, 편집할 때는 이 메모만 꺼내 쓴다 (영상을 매번 다시 읽지 않는다).
 */
export const ReferenceInsight = z.object({
  /** 이 영상이 전하려는 것 한두 문장 */
  purpose: z.string().max(300),
  /** 누구를 위한 영상인지 · 어떤 고민을 푸는지 */
  audience: z.string().max(200).default(''),
  /** 처음 몇 초를 어떻게 여는지 (질문·동작 먼저·결론 먼저 …) */
  hook: z.string().max(200).default(''),
  /** 말투 (존댓말·반말, 설명조·대화조, 쓰는 표현) */
  tone: z.string().max(200).default(''),
  /** 이야기 순서 */
  sections: z
    .array(z.object({ title: z.string().max(60), start: z.number().min(0), end: z.number().min(0), kind: InsightSectionKind.default('other') }))
    .default([]),
  /** 핵심 설명 문장 (그대로 옮긴 것) */
  keyPoints: z.array(z.string().max(200)).default([]),
  /** 지우면 안 되는 구간 — 동작 시범, 시범 중 침묵, 주의사항 */
  keepRanges: z.array(WhyRange).default([]),
  /** 반복 설명 · NG 후보 */
  cutCandidates: z.array(WhyRange).default([]),
  /** 독립된 숏폼이 될 만한 구간 + 이유 */
  shortCandidates: z.array(WhyRange.extend({ title: z.string().max(60) })).default([]),
  /** 운동 · 해부학 용어 (자막 오인식 교정에 쓴다) */
  terms: z.array(z.string().max(40)).default([]),
  /** 자막 길이 · 강조 방식 */
  subtitleNotes: z.string().max(200).default(''),
  /** 검색용 태그 — 부위 · 동작 · 고민 (예: 어깨, 견갑골, 거북목) */
  tags: z.array(z.string().max(30)).default([]),
  /** 어느 도구가 읽었는지 */
  provider: z.enum(['claude', 'codex']),
  createdAt: z.number().int(),
});
export type ReferenceInsight = z.infer<typeof ReferenceInsight>;

export const MemoryKind = z.enum(['style', 'keep', 'avoid', 'term']);
export type MemoryKind = z.infer<typeof MemoryKind>;
/** all = 앞으로 모든 영상, topic = 비슷한 주제(topics)에서만, video = 그 영상에서만 */
export const MemoryScope = z.enum(['all', 'topic', 'video']);
export type MemoryScope = z.infer<typeof MemoryScope>;
/** reference = 완성본들에서 AI 가 추린 것, feedback = 편집 중 사용자가 고쳐 달라고 한 것, user = 사용자가 직접 쓴 것 */
export const MemorySource = z.enum(['reference', 'feedback', 'user']);
export type MemorySource = z.infer<typeof MemorySource>;

/**
 * proposed = AI 가 완성본에서 추려 **제안한** 것. 사용자가 "쓰기"를 누르기 전엔 편집에 쓰지 않는다 (기획안 §12).
 * approved = 사용자가 확인한 것 · 편집 중 "앞으로도 이렇게" 한 것 · 직접 쓴 것.
 */
export const MemoryStatus = z.enum(['proposed', 'approved']);
export type MemoryStatus = z.infer<typeof MemoryStatus>;

/**
 * 제작자 기억 한 줄. 여러 완성본에 반복해서 나타나는 것만 남긴다.
 * 승인하지 않은 것을 영구 취향으로 굳히지 않는다: 완성본에서 온 것은 proposed 로 들어오고, 사용자가 확인해야 approved.
 * 사용자가 목록에서 보고 고치고 지울 수 있다.
 */
export const MemoryItem = z.object({
  id: z.string(),
  text: z.string().min(1).max(300),
  kind: MemoryKind,
  scope: MemoryScope,
  topics: z.array(z.string().max(30)).default([]),
  /** scope = video 일 때 */
  videoId: z.string().nullable().default(null),
  source: MemorySource,
  status: MemoryStatus.default('approved'),
  /** 근거가 된 완성본 id 들 */
  evidence: z.array(z.string()).default([]),
  createdAt: z.number().int(),
});
export type MemoryItem = z.infer<typeof MemoryItem>;

/** 에이전트가 편집 중에 남기는 기억 (update_style_rule 의 범위 있는 버전). */
export const RememberRequest = z.object({
  text: z.string().trim().min(2).max(300),
  kind: MemoryKind.default('style'),
  scope: MemoryScope.default('all'),
  topics: z.array(z.string().trim().min(1).max(30)).max(8).default([]),
});
export type RememberRequest = z.infer<typeof RememberRequest>;

/** 기억 한 줄 고치기: 글을 바꾸거나(text) 제안을 확인한다(status=approved). */
export const MemoryPatchRequest = z
  .object({
    text: z.string().trim().min(2).max(300).optional(),
    status: z.literal('approved').optional(),
  })
  .refine((v) => v.text !== undefined || v.status !== undefined, { message: 'nothing to change' });
export type MemoryPatchRequest = z.infer<typeof MemoryPatchRequest>;

/** 제안 여러 줄 한 번에 확인. ids 가 없으면 제안 전부. */
export const MemoryApproveRequest = z.object({ ids: z.array(z.string()).max(200).optional() });
export type MemoryApproveRequest = z.infer<typeof MemoryApproveRequest>;

/** 완성본 하나를 학습에서 빼거나 다시 넣는다 (파일은 그대로). */
export const ReferencePatchRequest = z.object({ excluded: z.boolean() });
export type ReferencePatchRequest = z.infer<typeof ReferencePatchRequest>;

/** downloading 은 링크 완성본만 (yt-dlp 로 받는 중). */
export const ReferenceStatus = z.enum(['queued', 'downloading', 'analyzing', 'done', 'failed', 'missing']);
export type ReferenceStatus = z.infer<typeof ReferenceStatus>;

/** folder = 완성본 폴더에서 훑은 파일, link = 유튜브·틱톡·릴스 링크에서 받은 영상 (~/.madi/references/) */
export const ReferenceSource = z.enum(['folder', 'link']);
export type ReferenceSource = z.infer<typeof ReferenceSource>;

export const Reference = z.object({
  id: z.string(),
  path: z.string(),
  fileName: z.string(),
  title: z.string(),
  sizeBytes: z.number().int(),
  status: ReferenceStatus,
  source: ReferenceSource,
  /** source = link 일 때 원래 링크 */
  url: z.string().nullable(),
  stats: ReferenceStats.nullable(),
  /** AI 가 자막을 읽고 남긴 메모. AI 가 연결돼 있고 소리가 있을 때만 생긴다. */
  insight: ReferenceInsight.nullable().default(null),
  /** 사용자가 학습에서 뺀 것 (기획안 §12). 숫자 · 기억 어디에도 안 쓴다. 파일은 그대로. */
  excluded: z.boolean().default(false),
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
  /** 링크로 배우기가 되는지 (이 PC 에 yt-dlp 가 있는지). 설치본은 항상 true. */
  linkImport: z.boolean(),
  /** 제작자 기억 (완성본에서 추린 것 + 편집 중 남긴 것). 사용자가 보고 지운다. */
  memory: z.array(MemoryItem).default([]),
  /** AI 가 연결돼 있어 완성본의 뜻까지 읽는지. 아니면 숫자만 배운다. */
  insightOn: z.boolean().default(false),
});
export type StyleResponse = z.infer<typeof StyleResponse>;

export const AddRuleRequest = z.object({ rule: z.string().trim().min(2).max(200) });
export type AddRuleRequest = z.infer<typeof AddRuleRequest>;

/** 링크로 배우기: 유튜브·틱톡·인스타 릴스 등 yt-dlp 가 읽는 공개 영상 주소. */
export const AddLinkRequest = z.object({ url: z.string().trim().min(8).max(2000) });
export type AddLinkRequest = z.infer<typeof AddLinkRequest>;

/** 링크 안에서 영상 주소 하나 고르기. http(s) 가 아니면 null. 브라우저·엔진이 같은 판단을 한다 (URL 클래스 없이 — shared 는 DOM/node 를 모른다). */
export function normalizeVideoUrl(input: string): string | null {
  const m = input.trim().match(/https?:\/\/[^\s<>"']+/i);
  if (!m) return null;
  const host = hostOf(m[0]);
  if (!host || !host.includes('.')) return null;
  return m[0].replace(/[.,;)]+$/, '');
}

function hostOf(url: string): string {
  const m = /^https?:\/\/(?:[^@/?#]*@)?([^/?#:\s]+)/i.exec(url);
  return (m?.[1] ?? '').toLowerCase().replace(/^www\./, '');
}

/** 화면에 보일 출처 이름 (유튜브 · 틱톡 · 인스타그램 · 그 외는 도메인). */
export function linkSiteLabel(url: string): string {
  const host = hostOf(url);
  if (host === 'youtu.be' || host.endsWith('youtube.com')) return '유튜브';
  if (host.endsWith('tiktok.com')) return '틱톡';
  if (host.endsWith('instagram.com')) return '인스타그램';
  return host;
}
