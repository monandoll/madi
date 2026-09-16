import { z } from 'zod';
import { VideoKind } from './video.js';

/** Edit 를 렌더한 결과 파일. */
export const Output = z.object({
  id: z.string(),
  videoId: z.string(),
  editId: z.string(),
  title: z.string(),
  kind: VideoKind,
  path: z.string(),
  durationSec: z.number(),
  width: z.number().int(),
  height: z.number().int(),
  sizeBytes: z.number().int(),
  createdAt: z.number().int(),
});
export type Output = z.infer<typeof Output>;
