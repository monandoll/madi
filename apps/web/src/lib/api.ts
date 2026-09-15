import { z } from 'zod';
import { HealthResponse, SettingsResponse, type SettingsPatch, VideosResponse } from '@madi/shared';

async function get<T>(path: string, schema: z.ZodType<T>): Promise<T> {
  const res = await fetch(path, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`${path} ${res.status}`);
  return schema.parse(await res.json());
}

async function patch<T>(path: string, body: unknown, schema: z.ZodType<T>): Promise<T> {
  const res = await fetch(path, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${path} ${res.status}`);
  return schema.parse(await res.json());
}

export const api = {
  health: () => get('/api/health', HealthResponse),
  videos: () => get('/api/videos', VideosResponse),
  settings: () => get('/api/settings', SettingsResponse),
  patchSettings: (body: SettingsPatch) => patch('/api/settings', body, SettingsResponse),
};

export const queryKeys = {
  health: ['health'] as const,
  videos: ['videos'] as const,
  settings: ['settings'] as const,
};
