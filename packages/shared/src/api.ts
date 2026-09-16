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

/** 영상 폴더 후보. 엔진이 PC에서 찾아 준다 — 사용자가 경로를 칠 일이 없게. */
export const FolderSuggestion = z.object({
  path: z.string(),
  /** 사람이 읽는 이름: 동영상, 바탕화면, 다운로드, 또는 폴더 이름 */
  label: z.string(),
  videoCount: z.number().int(),
  /** 이미 감시 중인 폴더인지 */
  selected: z.boolean(),
});
export type FolderSuggestion = z.infer<typeof FolderSuggestion>;

export const FoldersResponse = z.object({ folders: z.array(FolderSuggestion) });
export type FoldersResponse = z.infer<typeof FoldersResponse>;

/** 시스템 폴더 선택창 결과. 창을 못 띄우는 환경(브라우저만)이면 501. */
export const PickFolderResponse = z.object({ folder: FolderSuggestion.nullable() });
export type PickFolderResponse = z.infer<typeof PickFolderResponse>;

export const ErrorResponse = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});
export type ErrorResponse = z.infer<typeof ErrorResponse>;
