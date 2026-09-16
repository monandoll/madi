import fs from 'node:fs';
import path from 'node:path';
import { Hono } from 'hono';
import { serveStatic } from '@hono/node-server/serve-static';
import {
  ActionRequest,
  type ActionResponse,
  AddLinkRequest,
  AddRuleRequest,
  type StyleResponse,
  type AiProvidersResponse,
  ChatRequest,
  type ChatResponse,
  type FoldersResponse,
  type HealthResponse,
  type OpenFolderResponse,
  type Output,
  type OutputCard,
  type OutputDetailResponse,
  type OutputsResponse,
  type PickFolderResponse,
  type VideoDetailResponse,
  type Job,
  type JobsResponse,
  SettingsPatch,
  type SettingsResponse,
  type Video,
  type VideoCard,
  type VideosResponse,
} from '@madi/shared';
import type { EngineConfig } from '../config.js';
import type { JobQueue } from '../queue/index.js';
import type { SettingsStore } from '../settings.js';
import type { VideoStore } from '../videos.js';
import type { Library } from '../library.js';
import { ActionError, greetIfEmpty, runAction } from '../actions.js';
import { AgentError } from '../agent/runner.js';
import { detectCli } from '../agent/detect.js';
import { TOOL_NAMES, type ToolName } from '../mcp/tools.js';
import { describeFolder, openFolderWithSystem, suggestFolders } from '../folders.js';
import { LinkError } from '../style/service.js';
import { serveFile } from './media.js';

export interface AppDeps {
  cfg: EngineConfig;
  videos: VideoStore;
  queue: JobQueue;
  settings: SettingsStore;
  library: Library;
  events: import('../events.js').EventLog;
  tunnel: import('../tunnel.js').Tunnel;
  agent: import('../agent/runner.js').AgentRunner;
  agentTools: import('../agent/tools.js').AgentTools;
  styleService: import('../style/service.js').StyleService;
  chapters: import('../chapters/store.js').ChapterStore;
  version: string;
  onSettingsChanged?: () => void;
  /** 시스템 폴더 선택창. Electron 이 붙여 준다. 없으면 브라우저만 뜬 상태. */
  pickFolder?: (() => Promise<string | null>) | undefined;
  /** 폴더를 탐색기/Finder 로. Electron 은 shell.openPath, 없으면 OS 명령. */
  openFolder?: ((dir: string) => Promise<void>) | undefined;
}

export function toCard(v: Video, deps: Pick<AppDeps, 'videos' | 'queue' | 'library'>): VideoCard {
  const proxy = deps.videos.proxyOf(v.id);
  const thumb = deps.videos.thumbnailPath(v.id);
  const active = deps.queue.activeForVideo(v.id);
  return {
    ...v,
    thumbnailUrl: thumb && fs.existsSync(thumb) ? `/media/thumbs/${v.id}.jpg?v=${v.updatedAt}` : null,
    proxyUrl: proxy && fs.existsSync(proxy.path) ? `/media/proxies/${v.id}.mp4` : null,
    outputCount: deps.library.outputCount(v.id),
    activeJob: active ? { type: active.type, progress: active.progress } : null,
  };
}

export function toOutputCard(o: Output, cfg: EngineConfig): OutputCard {
  const thumb = path.join(cfg.outputsDir, `${o.id}.jpg`);
  return {
    ...o,
    url: `/media/outputs/${o.id}.mp4`,
    downloadUrl: `/media/outputs/${o.id}.mp4?download=1`,
    thumbnailUrl: fs.existsSync(thumb) ? `/media/outputs/${o.id}.jpg` : null,
  };
}

export function createApp(deps: AppDeps): Hono {
  const { cfg, videos, queue, settings } = deps;
  const app = new Hono();

  app.get('/api/health', async (c) => {
    const ai = await deps.agent.status();
    const body: HealthResponse = {
      ok: true,
      version: deps.version,
      ai,
      tunnel: { status: deps.tunnel.state.status, error: deps.tunnel.state.error },
    };
    return c.json(body);
  });

  app.get('/api/ai/providers', async (c) => {
    const [claude, codex] = await Promise.all([detectCli('claude', { fresh: c.req.query('fresh') === '1' }), detectCli('codex', { fresh: c.req.query('fresh') === '1' })]);
    const body: AiProvidersResponse = {
      providers: [
        { id: 'claude', label: 'Claude Code', installed: claude.installed, version: claude.version },
        { id: 'codex', label: 'Codex', installed: codex.installed, version: codex.version },
      ],
    };
    return c.json(body);
  });

  app.get('/api/videos', (c) => {
    const body: VideosResponse = { videos: videos.listVisible().map((v) => toCard(v, deps)) };
    return c.json(body);
  });

  app.get('/api/videos/:id', (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    if (v.status === 'ready') greetIfEmpty(deps.library, v);
    const body: VideoDetailResponse = {
      video: toCard(v, deps),
      transcript: deps.library.transcriptOf(v.id),
      outputs: deps.library.outputsOf(v.id).map((o) => toOutputCard(o, cfg)),
      messages: deps.library.messagesOf(v.id),
      jobs: queue.list(['queued', 'running']).filter((j) => j.videoId === v.id),
      aiBusy: deps.agent.isBusy(v.id),
      chapters: deps.chapters.get(v.id),
    };
    return c.json(body);
  });

  // AI 연결 뒤의 채팅. 미연결이면 러너를 스폰하지 않는다 (409 ai_off).
  app.post('/api/videos/:id/chat', async (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    if (v.status !== 'ready') return c.json({ error: { code: 'video_not_ready', message: 'video not ready' } }, 409);
    const parsed = ChatRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    try {
      const body: ChatResponse = { messages: deps.agent.ask(v, parsed.data.text) };
      return c.json(body);
    } catch (err) {
      if (err instanceof AgentError) return c.json({ error: { code: err.code, message: err.code } }, 409);
      throw err;
    }
  });

  app.post('/api/videos/:id/chat/cancel', (c) => {
    return c.json({ canceled: deps.agent.cancel(c.req.param('id')) });
  });

  // MCP 서버 프로세스 → 엔진. 러너가 준 토큰이 있어야 한다.
  app.post('/api/agent/tools/:name', async (c) => {
    if (c.req.header('x-madi-agent') !== deps.agent.token) return c.json({ error: { code: 'forbidden', message: 'bad agent token' } }, 403);
    const name = c.req.param('name');
    if (!(TOOL_NAMES as string[]).includes(name)) return c.json({ error: { code: 'unknown_tool', message: `unknown tool: ${name}` } }, 404);
    const body = (await c.req.json().catch(() => null)) as { videoId?: string; runId?: string; input?: unknown } | null;
    if (!body?.videoId) return c.json({ error: { code: 'bad_request', message: 'videoId required' } }, 400);
    const outcome = await deps.agentTools.call(name as ToolName, { videoId: body.videoId, runId: body.runId ?? '', signal: deps.agent.signalFor(body.runId ?? '') }, body.input);
    return c.json(outcome);
  });

  app.post('/api/videos/:id/actions', async (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    const parsed = ActionRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    try {
      const body: ActionResponse = runAction({ queue, videos, library: deps.library, events: deps.events }, v, parsed.data);
      return c.json(body);
    } catch (err) {
      if (err instanceof ActionError) return c.json({ error: { code: err.code, message: err.code } }, 409);
      throw err;
    }
  });

  app.get('/api/outputs', (c) => {
    const body: OutputsResponse = { outputs: deps.library.allOutputs().map((o) => toOutputCard(o, cfg)) };
    return c.json(body);
  });

  app.get('/api/outputs/:id', (c) => {
    const o = deps.library.output(c.req.param('id'));
    if (!o) return c.json({ error: { code: 'not_found', message: 'output not found' } }, 404);
    const edit = deps.library.edit(o.editId);
    const v = videos.get(o.videoId);
    if (!edit || !v) return c.json({ error: { code: 'not_found', message: 'output not found' } }, 404);
    const body: OutputDetailResponse = {
      output: toOutputCard(o, cfg),
      edit,
      transcript: (edit.transcriptId && deps.library.transcript(edit.transcriptId)) || deps.library.transcriptOf(v.id),
      video: toCard(v, deps),
    };
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
    const raw: unknown = await c.req.json().catch(() => null);
    const parsed = SettingsPatch.safeParse(raw);
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    // zod 는 partial 이어도 default 가 있는 키를 채워 넣는다 (setupDone=false 등). 보낸 키만 바꾼다.
    const sent = new Set(Object.keys((raw ?? {}) as object));
    const patch = Object.fromEntries(Object.entries(parsed.data).filter(([k]) => sent.has(k))) as typeof parsed.data;
    const next = settings.patch(patch);
    deps.onSettingsChanged?.();
    const body: SettingsResponse = { settings: next };
    return c.json(body);
  });

  // ---- 편집 스타일 (5단계) ----
  app.get('/api/style', (c) => {
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  app.post('/api/style/rules', async (c) => {
    const parsed = AddRuleRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    deps.agent.style.appendRule(parsed.data.rule);
    deps.styleService.emit('style.updated');
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  app.delete('/api/style/rules/:index', (c) => {
    const index = Number(c.req.param('index'));
    if (!Number.isInteger(index) || !deps.agent.style.removeRule(index)) return c.json({ error: { code: 'rule_locked', message: 'learned or missing rule' } }, 400);
    deps.styleService.emit('style.updated');
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 완성본 폴더를 다시 훑고, 실패한 것(링크 포함)도 다시 분석한다. */
  app.post('/api/style/relearn', (c) => {
    deps.styleService.refresh({ retryFailed: true });
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 링크로 배우기: 유튜브·틱톡·릴스 주소 → 받아서 완성본으로 분석. */
  app.post('/api/style/links', async (c) => {
    const parsed = AddLinkRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_link', message: parsed.error.message } }, 400);
    try {
      deps.styleService.addLink(parsed.data.url);
    } catch (err) {
      if (err instanceof LinkError) return c.json({ error: { code: err.code, message: err.code } }, err.code === 'no_downloader' ? 501 : 400);
      throw err;
    }
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 완성본 하나 빼기 (링크로 받은 것은 파일도 지운다). */
  app.delete('/api/style/references/:id', (c) => {
    if (!deps.styleService.removeReference(c.req.param('id'))) return c.json({ error: { code: 'not_found', message: 'reference not found' } }, 404);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  app.get('/api/folders/suggest', (c) => {
    const body: FoldersResponse = { folders: suggestFolders(settings.get().watchFolders) };
    return c.json(body);
  });

  /** 갤러리의 "폴더 열기": 첫 영상 폴더를 이 PC 의 탐색기/Finder 로 연다. 폴더가 없으면 opened=false. */
  app.post('/api/folders/open', async (c) => {
    const dir = settings.get().watchFolders.find((f) => fs.existsSync(f)) ?? null;
    if (!dir) {
      const body: OpenFolderResponse = { opened: false, path: null };
      return c.json(body);
    }
    try {
      await (deps.openFolder ?? openFolderWithSystem)(dir);
    } catch (err) {
      return c.json({ error: { code: 'open_failed', message: err instanceof Error ? err.message : String(err) } }, 500);
    }
    deps.events.record('folder.opened');
    const body: OpenFolderResponse = { opened: true, path: dir };
    return c.json(body);
  });

  app.post('/api/folders/pick', async (c) => {
    if (!deps.pickFolder) return c.json({ error: { code: 'no_picker', message: 'folder picker unavailable' } }, 501);
    const picked = await deps.pickFolder();
    const body: PickFolderResponse = { folder: picked ? describeFolder(picked, settings.get().watchFolders) : null };
    return c.json(body);
  });

  app.get('/media/thumbs/:file', (c) => {
    const id = safeId(c.req.param('file'), '.jpg');
    if (!id) return c.notFound();
    return serveFile(c, path.join(cfg.thumbsDir, `${id}.jpg`));
  });

  app.on(['GET', 'HEAD'], '/media/outputs/:file', (c) => {
    const file = c.req.param('file');
    const mp4 = safeId(file, '.mp4');
    const jpg = safeId(file, '.jpg');
    if (jpg) return serveFile(c, path.join(cfg.outputsDir, `${jpg}.jpg`));
    if (!mp4) return c.notFound();
    const o = deps.library.output(mp4);
    if (!o) return c.notFound();
    const res = serveFile(c, o.path);
    if (c.req.query('download') === '1' && res.status === 200) {
      const name = encodeURIComponent(`${o.title}.mp4`);
      res.headers.set('Content-Disposition', `attachment; filename*=UTF-8''${name}`);
    }
    return res;
  });

  app.on(['GET', 'HEAD'], '/media/proxies/:file', (c) => {
    const id = safeId(c.req.param('file'), '.mp4');
    if (!id) return c.notFound();
    return serveFile(c, path.join(cfg.proxiesDir, `${id}.mp4`));
  });

  return app;
}

/**
 * 웹 빌드 정적 서빙. SPA라서 못 찾으면 index.html.
 * /ws 업그레이드보다 뒤에 걸어야 하므로 API·WS 라우트를 다 붙인 다음 호출한다.
 */
export function mountWeb(app: Hono, cfg: EngineConfig): boolean {
  if (!fs.existsSync(path.join(cfg.webDir, 'index.html'))) return false;
  const root = path.relative(process.cwd(), cfg.webDir) || '.';
  app.use('/*', serveStatic({ root }));
  app.get('*', (c) => {
    if (c.req.path.startsWith('/api/') || c.req.path.startsWith('/media/') || c.req.path === '/ws') return c.notFound();
    return c.html(fs.readFileSync(path.join(cfg.webDir, 'index.html'), 'utf8'));
  });
  return true;
}

function safeId(file: string, ext: string): string | null {
  if (!file.endsWith(ext)) return null;
  const id = file.slice(0, -ext.length);
  return /^[A-Za-z0-9_-]+$/.test(id) ? id : null;
}
