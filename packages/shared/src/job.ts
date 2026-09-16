import { z } from 'zod';

export const JobType = z.enum(['probe', 'proxy', 'thumbnail', 'transcribe', 'silence', 'render']);
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

export const JobPayload = z.discriminatedUnion('type', [
  ProbeJobPayload,
  ProxyJobPayload,
  ThumbnailJobPayload,
  TranscribeJobPayload,
  SilenceJobPayload,
  RenderJobPayload,
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
};
