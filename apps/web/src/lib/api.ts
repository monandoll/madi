import { z } from 'zod';
import {
  type ActionRequest,
  ActionResponse,
  AiInstallResponse,
  AiPickResponse,
  AiProvidersResponse,
  ChatResponse,
  StyleResponse,
  FoldersResponse,
  HealthResponse,
  OpenFolderResponse,
  PairResponse,
  RemoteResponse,
  OutputDetailResponse,
  OutputsResponse,
  PickFolderResponse,
  SettingsResponse,
  type SettingsPatch,
  TranscriptResponse,
  VideoDetailResponse,
  VideosResponse,
  type PlanFeedbackRequest,
  PlanResponse,
  UpdateResponse,
} from '@madi/shared';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(`${status} ${code}`);
  }
}

/** 엔진이 돌려준 오류 코드. 없으면 http_error. */
async function errorOf(res: Response): Promise<ApiError> {
  const body = (await res.json().catch(() => null)) as { error?: { code?: string } } | null;
  return new ApiError(res.status, body?.error?.code ?? 'http_error');
}

async function get<T>(path: string, schema: z.ZodType<T>): Promise<T> {
  const res = await fetch(path, { headers: { accept: 'application/json' } });
  if (!res.ok) throw await errorOf(res);
  return schema.parse(await res.json());
}

async function send<T>(method: 'PATCH' | 'POST' | 'DELETE' | 'PUT', path: string, body: unknown, schema: z.ZodType<T>): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: body === undefined ? null : JSON.stringify(body),
  });
  if (!res.ok) throw await errorOf(res);
  return schema.parse(await res.json());
}

export const api = {
  health: () => get('/api/health', HealthResponse),
  /** 새 버전 상태 · 지금 확인 · 받아 둔 것으로 다시 시작 */
  update: () => get('/api/update', UpdateResponse),
  checkUpdate: () => send('POST', '/api/update/check', undefined, UpdateResponse),
  installUpdate: () => send('POST', '/api/update/install', undefined, UpdateResponse),
  videos: () => get('/api/videos', VideosResponse),
  settings: () => get('/api/settings', SettingsResponse),
  patchSettings: (body: SettingsPatch) => send('PATCH', '/api/settings', body, SettingsResponse),
  video: (id: string) => get(`/api/videos/${id}`, VideoDetailResponse),
  act: (id: string, body: ActionRequest) => send('POST', `/api/videos/${id}/actions`, body, ActionResponse),
  /** 편집안 후보 빼기 · 되돌리기 */
  planFeedback: (id: string, body: PlanFeedbackRequest) => send('POST', `/api/videos/${id}/plan/feedback`, body, PlanResponse),
  putTranscript: (id: string, segments: { start: number; end: number; text: string; secondaryText?: string }[], editId?: string) => send('PUT', `/api/videos/${id}/transcript`, { segments, ...(editId ? { editId } : {}) }, TranscriptResponse),
  chat: (id: string, text: string, editId?: string) => send('POST', `/api/videos/${id}/chat`, { text, editId }, ChatResponse),
  cancelChat: (id: string) => send('POST', `/api/videos/${id}/chat/cancel`, undefined, z.object({ canceled: z.boolean() })),
  aiProviders: (fresh = false) => get(`/api/ai/providers${fresh ? '?fresh=1' : ''}`, AiProvidersResponse),
  /** 이 PC 에서 도구를 어디에 뒀는지 직접 알려 주기. path 가 null 이면 직접 고른 것을 지운다. */
  aiSetPath: (provider: 'claude' | 'codex', path: string | null) => send('POST', '/api/ai/path', { provider, path }, AiProvidersResponse),
  /** 트레이 앱의 파일 선택창 열기 */
  aiPickPath: (provider: 'claude' | 'codex') => send('POST', '/api/ai/pick', { provider }, AiPickResponse),
  /** 마디가 대신 깔기 */
  aiInstallState: () => get('/api/ai/install', AiInstallResponse),
  aiInstall: (provider: 'claude' | 'codex') => send('POST', '/api/ai/install', { provider }, AiInstallResponse),
  aiInstallClear: () => send('DELETE', '/api/ai/install', undefined, AiInstallResponse),
  /** 로그인 창(터미널) 열기 */
  aiLogin: (provider: 'claude' | 'codex') => send('POST', '/api/ai/login', { provider }, z.object({ opened: z.literal(true) })),
  style: () => get('/api/style', StyleResponse),
  addRule: (rule: string) => send('POST', '/api/style/rules', { rule }, StyleResponse),
  removeRule: (index: number) => send('DELETE', `/api/style/rules/${index}`, undefined, StyleResponse),
  relearn: () => send('POST', '/api/style/relearn', undefined, StyleResponse),
  addLink: (url: string) => send('POST', '/api/style/links', { url }, StyleResponse),
  removeReference: (id: string) => send('DELETE', `/api/style/references/${id}`, undefined, StyleResponse),
  removeMemory: (id: string) => send('DELETE', `/api/style/memory/${id}`, undefined, StyleResponse),
  addMemory: (body: { text: string; kind?: string; scope?: string; topics?: string[] }) => send('POST', '/api/style/memory', body, StyleResponse),
  /** 글 고치기 또는 제안 확인 */
  patchMemory: (id: string, body: { text?: string; status?: 'approved' }) => send('PATCH', `/api/style/memory/${id}`, body, StyleResponse),
  /** 제안 전부(또는 ids) 확인 */
  approveMemory: (ids?: string[]) => send('POST', '/api/style/memory/approve', ids ? { ids } : {}, StyleResponse),
  /** 기억 전부 지우기 (onlyProposed 면 제안만) */
  clearMemory: (onlyProposed = false) => send('DELETE', `/api/style/memory${onlyProposed ? '?only=proposed' : ''}`, undefined, StyleResponse),
  /** 자막에서 고친 말 빼기 */
  removeCorrection: (id: string) => send('DELETE', `/api/style/corrections/${id}`, undefined, StyleResponse),
  /** 완성본을 학습에서 빼거나 다시 넣기 */
  patchReference: (id: string, excluded: boolean) => send('PATCH', `/api/style/references/${id}`, { excluded }, StyleResponse),
  outputs: () => get('/api/outputs', OutputsResponse),
  output: (id: string) => get(`/api/outputs/${id}`, OutputDetailResponse),
  suggestFolders: () => get('/api/folders/suggest', FoldersResponse),
  pickFolder: () => send('POST', '/api/folders/pick', undefined, PickFolderResponse),
  openFolder: () => send('POST', '/api/folders/open', undefined, OpenFolderResponse),
  remote: () => get('/api/remote', RemoteResponse),
  pair: (pin: string) => send('POST', '/api/remote/pair', { pin }, PairResponse),
};

export const queryKeys = {
  update: ['update'] as const,
  health: ['health'] as const,
  videos: ['videos'] as const,
  settings: ['settings'] as const,
  folders: ['folders'] as const,
  video: (id: string) => ['video', id] as const,
  outputs: ['outputs'] as const,
  output: (id: string) => ['output', id] as const,
  aiProviders: ['ai-providers'] as const,
  aiInstall: ['ai-install'] as const,
  style: ['style'] as const,
  remote: ['remote'] as const,
};
