import { z } from 'zod';
import { Video } from './video.js';
import { Job } from './job.js';
import { ChatMessage } from './chat.js';
import { Output } from './output.js';
import { Reference } from './style.js';

/** 엔진 → 브라우저. 갤러리와 진행 상태를 실시간으로 맞춘다. */
export const WsEvent = z.discriminatedUnion('type', [
  z.object({ type: z.literal('hello'), version: z.string() }),
  z.object({ type: z.literal('video.added'), video: Video }),
  z.object({ type: z.literal('video.updated'), video: Video }),
  z.object({ type: z.literal('video.removed'), videoId: z.string() }),
  z.object({ type: z.literal('job.updated'), job: Job }),
  z.object({ type: z.literal('message.added'), message: ChatMessage }),
  z.object({ type: z.literal('message.updated'), message: ChatMessage }),
  z.object({ type: z.literal('output.added'), output: Output }),
  z.object({ type: z.literal('reference.updated'), reference: Reference }),
  /** 규칙·배운 값이 바뀜. 설정 화면이 다시 읽는다. */
  z.object({ type: z.literal('style.updated') }),
]);
export type WsEvent = z.infer<typeof WsEvent>;
