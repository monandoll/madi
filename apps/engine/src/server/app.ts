import fs from 'node:fs';
import path from 'node:path';
import { Hono } from 'hono';
import { serveStatic } from '@hono/node-server/serve-static';
import {
  type HealthResponse,
  type Job,
  type JobsResponse,
  SettingsPatch,
  type SettingsResponse,
  type Video,
  type VideoCard,
  type VideoResponse,
  type VideosResponse,
} from '@madi/shared';
import type { EngineConfig } from '../config.js';
import type { JobQueue } from '../queue/index.js';
import type { SettingsStore } from '../settings.js';
import type { VideoStore } from '../videos.js';
import { serveFile } from './media.js';

export interface AppDeps {
  cfg: EngineConfig;
  videos: VideoStore;
  queue: JobQueue;
  settings: SettingsStore;
  version: string;
  onSettingsChanged?: () => void;
}

export function toCard(v: Video, deps: Pick<AppDeps, 'videos' | 'queue'>): VideoCard {
  const proxy = deps.videos.proxyOf(v.id);
  const thumb = deps.videos.thumbnailPath(v.id);
  const active = deps.queue.activeForVideo(v.id);
  return {
    ...v,
    thumbnailUrl: thumb && fs.existsSync(thumb) ? `/media/thumbs/${v.id}.jpg?v=${v.updatedAt}` : null,
    proxyUrl: proxy && fs.existsSync(proxy.path) ? `/media/proxies/${v.id}.mp4` : null,
    outputCount: 0,
    activeJob: active ? { type: active.type, progress: active.progress } : null,
  };
}

export function createApp(deps: AppDeps): Hono {
  const { cfg, videos, queue, settings } = deps;
  const app = new Hono();

  app.get('/api/health', (c) => {
    const body: HealthResponse = { ok: true, version: deps.version, ai: { connected: settings.get().ai.provider !== 'none' } };
    return c.json(body);
  });

  app.get('/api/videos', (c) => {
    const body: VideosResponse = { videos: videos.list().map((v) => toCard(v, deps)) };
    return c.json(body);
  });

  app.get('/api/videos/:id', (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    const body: VideoResponse = { video: toCard(v, deps) };
    return c.json(body);
  });

  app.get('/api/jobs', (c) => {
    const status = c.req.query('status');
    const statuses = status ? (status.split(',') as Job['status'][]) : undefined;
    const body: JobsResponse = { jobs: queue.list(statuses) };
    return c.json(body);
  });

  app.get('/api/settings', (c) => {
    const body: SettingsResponse = { settings: settings.get() };
    return c.json(body);
  });

  app.patch('/api/settings', async (c) => {
    const parsed = SettingsPatch.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    const next = settings.patch(parsed.data);
    deps.onSettingsChanged?.();
    const body: SettingsResponse = { settings: next };
    return c.json(body);
  });

  app.get('/media/thumbs/:file', (c) => {
    const id = safeId(c.req.param('file'), '.jpg');
    if (!id) return c.notFound();
    return serveFile(c, path.join(cfg.thumbsDir, `${id}.jpg`));
  });

  app.on(['GET', 'HEAD'], '/media/proxies/:file', (c) => {
    const id = safeId(c.req.param('file'), '.mp4');
    if (!id) return c.notFound();
    return serveFile(c, path.join(cfg.proxiesDir, `${id}.mp4`));
  });

  // 웹 빌드 정적 서빙. SPA라서 못 찾으면 index.html.
  if (fs.existsSync(cfg.webDir)) {
    const root = path.relative(process.cwd(), cfg.webDir) || '.';
    app.use('/*', serveStatic({ root }));
    app.get('*', (c) => {
      if (c.req.path.startsWith('/api/') || c.req.path.startsWith('/media/')) return c.notFound();
      return c.html(fs.readFileSync(path.join(cfg.webDir, 'index.html'), 'utf8'));
    });
  }

  return app;
}

function safeId(file: string, ext: string): string | null {
  if (!file.endsWith(ext)) return null;
  const id = file.slice(0, -ext.length);
  return /^[A-Za-z0-9_-]+$/.test(id) ? id : null;
}
