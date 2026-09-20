import { z } from 'zod';
import { TimeRange } from './transcript.js';

/** 원본 화면 표본. 결과물 선택 시 컷·조각 순서를 반영한다. */
export const VideoFramesRequest = z.object({
  editId: z.string().optional(),
  range: TimeRange.refine(r => r.end > r.start, 'end must follow start').optional().describe('더 자세히 볼 원본 구간(초). 생략하면 선택한 결과물 전체'),
  count: z.number().int().min(4).max(16).default(12),
});
export type VideoFramesRequest = z.infer<typeof VideoFramesRequest>;

export const VideoFramesSummary = z.object({
  videoId: z.string(),
  editId: z.string().nullable(),
  sourceDurationSec: z.number(),
  sheets: z.array(z.object({
    columns: z.number().int(),
    frames: z.array(z.object({ sourceTime: z.number(), outputTime: z.number() })),
  })),
  note: z.string(),
});
export type VideoFramesSummary = z.infer<typeof VideoFramesSummary>;
