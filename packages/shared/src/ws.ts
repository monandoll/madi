import { z } from 'zod';
import { Video } from './video.js';
import { Job } from './job.js';

/** 엔진 → 브라우저. 갤러리와 진행 상태를 실시간으로 맞춘다. */
export const WsEvent = z.discriminatedUnion('type', [
  z.object({ type: z.literal('hello'), version: z.string() }),
  z.object({ type: z.literal('video.added'), video: Video }),
  z.object({ type: z.literal('video.updated'), video: Video }),
  z.object({ type: z.literal('video.removed'), videoId: z.string() }),
  z.object({ type: z.literal('job.updated'), job: Job }),
]);
export type WsEvent = z.infer<typeof WsEvent>;
