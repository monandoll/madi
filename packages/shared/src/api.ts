import { z } from 'zod';
import { Video } from './video.js';
import { Job } from './job.js';
import { AiProvider, RemoteMode, Settings } from './settings.js';
import { Transcript, TimeRange } from './transcript.js';
import { Edit } from './edit.js';
import { Output } from './output.js';
import { ChatMessage } from './chat.js';
import { Chapters } from './chapter.js';
import { EditPlan, PlanFeedbackKind, PlanVerdict } from './plan.js';

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

/** 영상 상세: 카드 + 자막 + 결과물 + 대화 + 돌고 있는 잡 + 에이전트가 답하는 중인지. */
export const VideoDetailResponse = z.object({
  video: VideoCard,
  transcript: Transcript.nullable(),
  outputs: z.array(OutputCard),
  messages: z.array(ChatMessage),
  jobs: z.array(Job),
  aiBusy: z.boolean().default(false),
  /** 롱폼 챕터 (나눈 적 있을 때) */
  chapters: Chapters.nullable().default(null),
  /** 편집안 (AI 가 읽은 적 있을 때) */
  plan: EditPlan.nullable().default(null),
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
  /** from: 어디서 골랐는지 — 직접 구간 선택 · 챕터 카드 · 편집안 카드. 기록(events)에만 쓴다 (기획안 §9: 무엇을 골랐는지가 피드백). */
  z.object({ type: z.literal('short'), range: TimeRange, subtitles: z.boolean().default(true), from: z.enum(['manual', 'chapter', 'plan']).default('manual') }),
  /** 롱폼: 챕터 나누기 (자막 없으면 먼저 만든다) */
  z.object({ type: z.literal('chapters') }),
  /** 롱폼: 챕터마다 숏폼 하나씩 자동으로 (max 개까지) */
  z.object({ type: z.literal('auto_shorts'), max: z.number().int().min(1).max(10).default(3) }),
  /** 편집안 만들기 (AI 연결 필요 — 없으면 409 ai_off). 다시 부르면 새로 읽는다. */
  z.object({ type: z.literal('plan') }),
  /** 편집안대로 롱폼 만들기: 잘라낼 후보를 빼고(남길 구간은 건드리지 않고) 렌더 */
  z.object({ type: z.literal('apply_plan') }),
]);
export type ActionRequest = z.infer<typeof ActionRequest>;

export const ActionResponse = z.object({ messages: z.array(ChatMessage), job: Job.nullable() });

/** 편집안 후보에 판단 남기기. verdict 가 null 이면 지운다 (되돌리기). */
export const PlanFeedbackRequest = z.object({ kind: PlanFeedbackKind, index: z.number().int().min(0), verdict: PlanVerdict.nullable() });
export type PlanFeedbackRequest = z.infer<typeof PlanFeedbackRequest>;
export const PlanResponse = z.object({ plan: EditPlan });
export type PlanResponse = z.infer<typeof PlanResponse>;

/** 자막 직접 쓰기/고치기: 자막 전체를 이 줄들로 바꾼다 (소리 없는 영상도 됨). */
export const TranscriptPutRequest = z.object({
  segments: z.array(z.object({ start: z.number().min(0), end: z.number().min(0), text: z.string().trim().min(1).max(200) })).min(1).max(500),
});
export type TranscriptPutRequest = z.infer<typeof TranscriptPutRequest>;
export const TranscriptResponse = z.object({ transcript: Transcript });
export type TranscriptResponse = z.infer<typeof TranscriptResponse>;
export type ActionResponse = z.infer<typeof ActionResponse>;

/**
 * AI 연결 뒤의 채팅. 문장 하나를 보내면 엔진이 사용자 말풍선 + (쓰는 중인) 답 말풍선을 만들고
 * 에이전트를 띄운다. 답은 WS message.updated 로 채워진다.
 */
export const ChatRequest = z.object({ text: z.string().trim().min(1).max(2000) });
export type ChatRequest = z.infer<typeof ChatRequest>;

export const ChatResponse = z.object({ messages: z.array(ChatMessage) });
export type ChatResponse = z.infer<typeof ChatResponse>;

/** 이 PC 에 설치된 AI 도구. 사용자는 이 중 하나를 고른다. */
export const AiProviderInfo = z.object({
  id: AiProvider.exclude(['none']),
  /** 화면에 보이는 이름 */
  label: z.string(),
  installed: z.boolean(),
  version: z.string().nullable(),
  /** 이 PC 에서 찾은 실행 파일. 못 찾았으면 null. */
  path: z.string().nullable().default(null),
  /** 사용자가 직접 골라 준 파일인가 (PC 마다 설치 위치가 달라서). */
  custom: z.boolean().default(false),
  /** 이 PC 에서 마디가 대신 깔아 줄 수 있는가 (공식 설치기가 있는 OS). */
  canInstall: z.boolean().default(false),
  /** 터미널에 직접 칠 사람을 위한 한 줄. 못 깔아 주는 OS 면 null. */
  installLine: z.string().nullable().default(null),
});
export type AiProviderInfo = z.infer<typeof AiProviderInfo>;

export const AiProvidersResponse = z.object({ providers: z.array(AiProviderInfo) });
export type AiProvidersResponse = z.infer<typeof AiProvidersResponse>;

/**
 * 도구를 이 PC 어디에 뒀는지 직접 알려 주기. path 가 null 이면 직접 고른 것을 지우고 다시 찾는다.
 * 실행해 보고 안 되면 400 `ai_path_bad`.
 */
export const AiPathRequest = z.object({
  provider: AiProvider.exclude(['none']),
  path: z.string().trim().min(1).max(4096).nullable(),
});
export type AiPathRequest = z.infer<typeof AiPathRequest>;

/**
 * 마디가 대신 깔기. 한 번에 하나만.
 * step 은 사용자에게 보여 줄 단계, error 는 왜 안 됐는지 (network/permission/unsupported/…).
 */
export const AiInstallState = z.object({
  provider: AiProvider.exclude(['none']).nullable(),
  status: z.enum(['idle', 'running', 'done', 'failed']),
  step: z.enum(['downloading', 'checking']).nullable().default(null),
  error: z.string().nullable().default(null),
});
export type AiInstallState = z.infer<typeof AiInstallState>;

export const AiInstallRequest = z.object({ provider: AiProvider.exclude(['none']) });
export type AiInstallRequest = z.infer<typeof AiInstallRequest>;

/** 깔기 상태 + 지금 찾은 결과 (끝나면 바로 연결까지 이어지게). */
export const AiInstallResponse = z.object({ install: AiInstallState, providers: z.array(AiProviderInfo) });
export type AiInstallResponse = z.infer<typeof AiInstallResponse>;

/**
 * 화면 안 터미널에서 열 수 있는 것. **이 목록이 전부다** — 셸도, 사용자가 친 명령도 없다.
 * 짝지은 폰이 이 PC 를 마음대로 조종하지 못하게 하려는 것.
 */
export const TermKind = z.enum(['login-claude', 'login-codex', 'install-claude', 'install-codex']);
export type TermKind = z.infer<typeof TermKind>;

/** 브라우저 → 엔진 (터미널 소켓) */
export const TermIn = z.union([
  z.object({ t: z.literal('open'), kind: TermKind, cols: z.number(), rows: z.number() }),
  z.object({ t: z.literal('in'), d: z.string().max(4096) }),
  z.object({ t: z.literal('size'), cols: z.number(), rows: z.number() }),
  z.object({ t: z.literal('kill') }),
]);
export type TermIn = z.infer<typeof TermIn>;

/** 엔진 → 브라우저 */
export const TermOut = z.union([
  z.object({ t: z.literal('ready'), title: z.string(), line: z.string().nullable() }),
  z.object({ t: z.literal('out'), d: z.string() }),
  z.object({ t: z.literal('exit'), code: z.number() }),
  // no_pty: 도구는 있는데 이 PC 에서 터미널을 못 띄웠다. line 은 사용자가 직접 칠 한 줄 (막다른 길을 만들지 않는다).
  z.object({ t: z.literal('error'), code: z.enum(['not_found', 'busy', 'bad_kind', 'no_pty']), line: z.string().nullable().default(null) }),
]);
export type TermOut = z.infer<typeof TermOut>;

/** 파일 고르기(트레이 앱의 파일 선택창). canceled 면 사용자가 창을 닫은 것. */
export const AiPickResponse = z.object({
  canceled: z.boolean(),
  provider: AiProviderInfo.nullable(),
});
export type AiPickResponse = z.infer<typeof AiPickResponse>;

export const JobsResponse = z.object({ jobs: z.array(Job) });
export type JobsResponse = z.infer<typeof JobsResponse>;

export const SettingsResponse = z.object({ settings: Settings });
export type SettingsResponse = z.infer<typeof SettingsResponse>;

export const TunnelStatus = z.enum(['off', 'starting', 'running', 'error']);
export type TunnelStatus = z.infer<typeof TunnelStatus>;

/**
 * 밖에서 접속하기 상태. `url` 은 폰이 들어올 주소 (QR 로 보여 준다).
 * `pin` 은 이 PC 화면에서만 보인다 — 폰에서 부르면 null.
 */
export const RemoteResponse = z.object({
  mode: RemoteMode,
  status: TunnelStatus,
  url: z.string().nullable(),
  error: z.string().nullable(),
  pin: z.string().nullable(),
  /** 짝지어 둔 기기 수 */
  devices: z.number().int().min(0),
});
export type RemoteResponse = z.infer<typeof RemoteResponse>;

export const PairRequest = z.object({ pin: z.string().trim().min(4).max(12) });
export type PairRequest = z.infer<typeof PairRequest>;
export const PairResponse = z.object({ ok: z.literal(true) });
export type PairResponse = z.infer<typeof PairResponse>;

export const HealthResponse = z.object({
  ok: z.literal(true),
  version: z.string(),
  /** connected = 프로바이더를 골랐고 그 도구가 이 PC 에 있다. */
  ai: z.object({ connected: z.boolean(), provider: AiProvider, installed: z.boolean() }),
  tunnel: z.object({ status: TunnelStatus, error: z.string().nullable(), url: z.string().nullable().default(null) }),
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

/** PC 의 영상 폴더를 탐색기/Finder 로 연 결과. 폴더가 없으면 opened=false. */
export const OpenFolderResponse = z.object({ opened: z.boolean(), path: z.string().nullable() });
export type OpenFolderResponse = z.infer<typeof OpenFolderResponse>;

export const ErrorResponse = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});
export type ErrorResponse = z.infer<typeof ErrorResponse>;
