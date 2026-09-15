import { z } from 'zod';

/** 원본 영상. 상태는 엔진이 잡 진행에 따라 바꾼다. */
export const VideoKind = z.enum(['long', 'short']);
export type VideoKind = z.infer<typeof VideoKind>;

/**
 * registered: 파일을 발견해 DB에 넣음 (아직 probe 전)
 * preparing:  probe 끝, 프록시·썸네일 만드는 중
 * ready:      프록시·썸네일 준비됨
 * failed:     probe 또는 프록시 실패 (UI에는 AI 말투 문구로)
 * missing:    감시 폴더에서 파일이 사라짐
 */
export const VideoStatus = z.enum(['registered', 'preparing', 'ready', 'failed', 'missing']);
export type VideoStatus = z.infer<typeof VideoStatus>;

export const Video = z.object({
  id: z.string(),
  path: z.string(),
  fileName: z.string(),
  title: z.string(),
  kind: VideoKind,
  status: VideoStatus,
  durationSec: z.number().nullable(),
  width: z.number().int().nullable(),
  height: z.number().int().nullable(),
  fps: z.number().nullable(),
  hasAudio: z.boolean().nullable(),
  sizeBytes: z.number().int(),
  /** 파일 시스템 mtime (ms). 갤러리 정렬 기준. */
  recordedAt: z.number().int(),
  createdAt: z.number().int(),
  updatedAt: z.number().int(),
  error: z.string().nullable(),
});
export type Video = z.infer<typeof Video>;

export const Proxy = z.object({
  id: z.string(),
  videoId: z.string(),
  path: z.string(),
  width: z.number().int(),
  height: z.number().int(),
  createdAt: z.number().int(),
});
export type Proxy = z.infer<typeof Proxy>;

/** 60초 이하면 숏폼으로 본다. */
export const SHORT_MAX_SEC = 60;
export function kindFromDuration(durationSec: number): VideoKind {
  return durationSec <= SHORT_MAX_SEC ? 'short' : 'long';
}

/** 파일명에서 확장자를 뗀 것이 기본 제목. */
export function titleFromFileName(fileName: string): string {
  return fileName.replace(/\.[^.]+$/, '');
}

export const VIDEO_EXTENSIONS = ['.mp4', '.mov', '.m4v', '.mkv', '.avi', '.webm', '.mts', '.m2ts'] as const;
export function isVideoFile(fileName: string): boolean {
  const lower = fileName.toLowerCase();
  return VIDEO_EXTENSIONS.some((ext) => lower.endsWith(ext));
}
