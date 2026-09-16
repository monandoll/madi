import { z } from 'zod';
import { Video } from './video.js';
import { Job } from './job.js';
import { Settings } from './settings.js';
import { Transcript, TimeRange } from './transcript.js';
import { Edit } from './edit.js';
import { Output } from './output.js';
import { ChatMessage } from './chat.js';

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

/** 결과물 카드: 파일 URL 과 다운로드 URL. */
export const OutputCard = Output.extend({
  url: z.string(),
  downloadUrl: z.string(),
  thumbnailUrl: z.string().nullable(),
});
export type OutputCard = z.infer<typeof OutputCard>;

export const VideosResponse = z.object({ videos: z.array(VideoCard) });
export type VideosResponse = z.infer<typeof VideosResponse>;

/** 영상 상세: 카드 + 자막 + 결과물 + 대화 + 돌고 있는 잡. */
export const VideoDetailResponse = z.object({
  video: VideoCard,
  transcript: Transcript.nullable(),
  outputs: z.array(OutputCard),
  messages: z.array(ChatMessage),
  jobs: z.array(Job),
});
export type VideoDetailResponse = z.infer<typeof VideoDetailResponse>;

export const OutputsResponse = z.object({ outputs: z.array(OutputCard) });
export type OutputsResponse = z.infer<typeof OutputsResponse>;

export const OutputDetailResponse = z.object({
  output: OutputCard,
  edit: Edit,
  transcript: Transcript.nullable(),
  video: VideoCard,
});
export type OutputDetailResponse = z.infer<typeof OutputDetailResponse>;

/**
 * AI 미연결 상태의 버튼 4개. 워커를 직접 부른다.
 * - subtitle: 자막 만들기 (없으면) → 자막 번인 결과물
 * - silence:  쉬는 구간 잘라내기
 * - vertical: 세로(9:16)로 바꾸기
 * - short:    구간 하나를 세로 숏폼으로
 */
export const ActionRequest = z.discriminatedUnion('type', [
  z.object({ type: z.literal('subtitle') }),
  z.object({ type: z.literal('silence') }),
  z.object({ type: z.literal('vertical') }),
  z.object({ type: z.literal('short'), range: TimeRange, subtitles: z.boolean().default(true) }),
]);
export type ActionRequest = z.infer<typeof ActionRequest>;

export const ActionResponse = z.object({ messages: z.array(ChatMessage), job: Job.nullable() });
export type ActionResponse = z.infer<typeof ActionResponse>;

export const JobsResponse = z.object({ jobs: z.array(Job) });
export type JobsResponse = z.infer<typeof JobsResponse>;

export const SettingsResponse = z.object({ settings: Settings });
export type SettingsResponse = z.infer<typeof SettingsResponse>;

export const TunnelStatus = z.enum(['off', 'starting', 'running', 'error']);
export type TunnelStatus = z.infer<typeof TunnelStatus>;

export const HealthResponse = z.object({
  ok: z.literal(true),
  version: z.string(),
  ai: z.object({ connected: z.boolean() }),
  tunnel: z.object({ status: TunnelStatus, error: z.string().nullable() }),
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
