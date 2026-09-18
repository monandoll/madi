import { z } from 'zod';

export const JobType = z.enum(['probe', 'proxy', 'thumbnail', 'transcribe', 'silence', 'render', 'analyze', 'chapters', 'download', 'insight', 'plan']);
export type JobType = z.infer<typeof JobType>;

export const JobStatus = z.enum(['queued', 'running', 'done', 'failed', 'canceled']);
export type JobStatus = z.infer<typeof JobStatus>;

export const ProbeJobPayload = z.object({ type: z.literal('probe'), videoId: z.string() });
export const ProxyJobPayload = z.object({ type: z.literal('proxy'), videoId: z.string() });
export const ThumbnailJobPayload = z.object({ type: z.literal('thumbnail'), videoId: z.string() });
export const TranscribeJobPayload = z.object({
  type: z.literal('transcribe'),
  videoId: z.string(),
  /** 자막이 필요한 렌더가 기다리면 그 Edit. 자막 만들고 바로 렌더로 이어간다. */
  renderEditId: z.string().nullable().optional(),
});
/** 무음 구간 찾기 → 그 결과로 Edit 을 만들어 render 로 이어간다 */
export const SilenceJobPayload = z.object({ type: z.literal('silence'), videoId: z.string(), editId: z.string() });
export const RenderJobPayload = z.object({ type: z.literal('render'), videoId: z.string(), editId: z.string() });
/** 완성본 하나 분석 (5단계 스타일 학습). 영상(videoId)이 아니라 완성본(referenceId)에 붙는다. */
export const AnalyzeJobPayload = z.object({ type: z.literal('analyze'), referenceId: z.string() });
/** 링크 완성본 받기 (yt-dlp). 끝나면 analyze 로 이어진다. */
export const DownloadJobPayload = z.object({ type: z.literal('download'), referenceId: z.string() });
/** 완성본의 뜻 읽기 (AI 가 자막을 읽고 메모). analyze 뒤에, AI 가 연결돼 있을 때만. */
export const InsightJobPayload = z.object({ type: z.literal('insight'), referenceId: z.string() });
/** 촬영본 편집안 (AI 한 턴, 도구 없음). 자막이 없고 소리가 있으면 먼저 만든다. */
export const PlanJobPayload = z.object({ type: z.literal('plan'), videoId: z.string() });
/** 롱폼 챕터 나누기. then='shorts' 면 챕터마다 숏폼 렌더까지. */
export const ChaptersJobPayload = z.object({
  type: z.literal('chapters'),
  videoId: z.string(),
  then: z.enum(['none', 'shorts']).default('none'),
  max: z.number().int().min(1).max(10).default(3),
});

export const JobPayload = z.discriminatedUnion('type', [
  ProbeJobPayload,
  ProxyJobPayload,
  ThumbnailJobPayload,
  TranscribeJobPayload,
  SilenceJobPayload,
  RenderJobPayload,
  AnalyzeJobPayload,
  ChaptersJobPayload,
  DownloadJobPayload,
  InsightJobPayload,
  PlanJobPayload,
]);
export type JobPayload = z.infer<typeof JobPayload>;

export const Job = z.object({
  id: z.string(),
  type: JobType,
  status: JobStatus,
  /** 0..1 */
  progress: z.number().min(0).max(1),
  videoId: z.string().nullable(),
  payload: JobPayload,
  error: z.string().nullable(),
  attempts: z.number().int(),
  createdAt: z.number().int(),
  startedAt: z.number().int().nullable(),
  finishedAt: z.number().int().nullable(),
});
export type Job = z.infer<typeof Job>;

/** 타입별 동시 실행 수. 렌더 1, 자막 1. 프록시·썸네일은 가벼워서 2. */
export const JOB_CONCURRENCY: Record<JobType, number> = {
  probe: 2,
  proxy: 1,
  thumbnail: 2,
  transcribe: 1,
  silence: 1,
  render: 1,
  analyze: 1,
  chapters: 1,
  download: 1,
  // AI 한 턴 (완성본 하나 읽기). 동시에 여러 개 띄우지 않는다.
  insight: 1,
  // AI 한 턴 (촬영본 편집안)
  plan: 1,
};
