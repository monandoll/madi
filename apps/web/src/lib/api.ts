import { z } from 'zod';
import {
  type ActionRequest,
  ActionResponse,
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
  videos: () => get('/api/videos', VideosResponse),
  settings: () => get('/api/settings', SettingsResponse),
  patchSettings: (body: SettingsPatch) => send('PATCH', '/api/settings', body, SettingsResponse),
  video: (id: string) => get(`/api/videos/${id}`, VideoDetailResponse),
  act: (id: string, body: ActionRequest) => send('POST', `/api/videos/${id}/actions`, body, ActionResponse),
  putTranscript: (id: string, segments: { start: number; end: number; text: string }[]) => send('PUT', `/api/videos/${id}/transcript`, { segments }, TranscriptResponse),
  chat: (id: string, text: string) => send('POST', `/api/videos/${id}/chat`, { text }, ChatResponse),
  cancelChat: (id: string) => send('POST', `/api/videos/${id}/chat/cancel`, undefined, z.object({ canceled: z.boolean() })),
  aiProviders: (fresh = false) => get(`/api/ai/providers${fresh ? '?fresh=1' : ''}`, AiProvidersResponse),
  style: () => get('/api/style', StyleResponse),
  addRule: (rule: string) => send('POST', '/api/style/rules', { rule }, StyleResponse),
  removeRule: (index: number) => send('DELETE', `/api/style/rules/${index}`, undefined, StyleResponse),
  relearn: () => send('POST', '/api/style/relearn', undefined, StyleResponse),
  addLink: (url: string) => send('POST', '/api/style/links', { url }, StyleResponse),
  removeReference: (id: string) => send('DELETE', `/api/style/references/${id}`, undefined, StyleResponse),
  outputs: () => get('/api/outputs', OutputsResponse),
  output: (id: string) => get(`/api/outputs/${id}`, OutputDetailResponse),
  suggestFolders: () => get('/api/folders/suggest', FoldersResponse),
  pickFolder: () => send('POST', '/api/folders/pick', undefined, PickFolderResponse),
  openFolder: () => send('POST', '/api/folders/open', undefined, OpenFolderResponse),
  remote: () => get('/api/remote', RemoteResponse),
  pair: (pin: string) => send('POST', '/api/remote/pair', { pin }, PairResponse),
};

export const queryKeys = {
  health: ['health'] as const,
  videos: ['videos'] as const,
  settings: ['settings'] as const,
  folders: ['folders'] as const,
  video: (id: string) => ['video', id] as const,
  outputs: ['outputs'] as const,
  output: (id: string) => ['output', id] as const,
  aiProviders: ['ai-providers'] as const,
  style: ['style'] as const,
  remote: ['remote'] as const,
};
