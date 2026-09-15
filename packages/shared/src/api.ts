import { z } from 'zod';
import { Video } from './video.js';
import { Job } from './job.js';
import { Settings } from './settings.js';

export const ENGINE_PORT = 41520;

/** 갤러리 카드 하나. Video에 브라우저가 쓸 URL과 파생 정보를 붙인 것. */
export const VideoCard = Video.extend({
  thumbnailUrl: z.string().nullable(),
  proxyUrl: z.string().nullable(),
  outputCount: z.number().int(),
  /** 진행 중인 잡 (없으면 null). 갤러리 상태 배지에 쓴다. */
  activeJob: Job.pick({ type: true, progress: true }).nullable(),
});
export type VideoCard = z.infer<typeof VideoCard>;

export const VideosResponse = z.object({ videos: z.array(VideoCard) });
export type VideosResponse = z.infer<typeof VideosResponse>;

export const VideoResponse = z.object({ video: VideoCard });
export type VideoResponse = z.infer<typeof VideoResponse>;

export const JobsResponse = z.object({ jobs: z.array(Job) });
export type JobsResponse = z.infer<typeof JobsResponse>;

export const SettingsResponse = z.object({ settings: Settings });
export type SettingsResponse = z.infer<typeof SettingsResponse>;

export const HealthResponse = z.object({
  ok: z.literal(true),
  version: z.string(),
  ai: z.object({ connected: z.boolean() }),
});
export type HealthResponse = z.infer<typeof HealthResponse>;

export const ErrorResponse = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});
export type ErrorResponse = z.infer<typeof ErrorResponse>;
