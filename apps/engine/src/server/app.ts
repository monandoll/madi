import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { type Context, Hono } from 'hono';
import type { HttpBindings } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { RESPONSE_ALREADY_SENT } from '@hono/node-server/utils/response';
import {
  ActionRequest,
  type ActionResponse,
  type UpdateResponse,
  PlanFeedbackRequest,
  type PlanResponse,
  planRejected,
  AddLinkRequest,
  AddRuleRequest,
  RememberRequest,
  MemoryPatchRequest,
  MemoryApproveRequest,
  ReferencePatchRequest,
  type StyleResponse,
  AiInstallRequest,
  type AiInstallResponse,
  AiPathRequest,
  type AiPickResponse,
  type AiProviderInfo,
  type AiProvidersResponse,
  ChatRequest,
  type ChatResponse,
  type FoldersResponse,
  type HealthResponse,
  type OpenFolderResponse,
  PairRequest,
  type PairResponse,
  type RemoteResponse,
  type Output,
  type OutputCard,
  type OutputDetailResponse,
  type OutputsResponse,
  type PickFolderResponse,
  type VideoDetailResponse,
  TranscriptPutRequest,
  type TranscriptResponse,
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
import type { UpdateStatus } from '../update.js';
import { rejectionMemory } from '../plan/prompt.js';
import { type CorrectionStore, diffCorrections } from '../style/corrections.js';
import { ActionError, greetIfEmpty, runAction } from '../actions.js';
import { AgentError } from '../agent/runner.js';
import { cliVersion, detectCli } from '../agent/detect.js';
import { installLine, loginPlan } from '../agent/install.js';
import { TOOL_NAMES, type ToolName } from '../mcp/tools.js';
import { describeFolder, openFolderWithSystem, suggestFolders } from '../folders.js';
import { LinkError } from '../style/service.js';
import { isDirectRequest, PAIR_COOKIE, readCookie } from '../remote.js';
import { mergeSubtitleLines } from '../agent/subtitles.js';
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
  /** 제작자 기억 (설정에서 보고 지운다). */
  memory: import('../style/memory.js').MemoryStore;
  corrections: CorrectionStore;
  /** 새 버전 상태 */
  update: UpdateStatus;
  chapters: import('../chapters/store.js').ChapterStore;
  /** 촬영본 편집안 */
  plans: import('../plan/store.js').PlanStore;
  version: string;
  onSettingsChanged?: () => void;
  /** 시스템 폴더 선택창. Electron 이 붙여 준다. 없으면 브라우저만 뜬 상태. */
  pickFolder?: (() => Promise<string | null>) | undefined;
  /** Electron 이 파일 선택창을 붙인다 (AI 도구 실행 파일 직접 고르기). */
  pickFile?: (() => Promise<string | null>) | undefined;
  /** 폴더를 탐색기/Finder 로. Electron 은 shell.openPath, 없으면 OS 명령. */
  openFolder?: ((dir: string) => Promise<void>) | undefined;
  /** 폰에서 올리기 (tus). node 의 req/res 를 그대로 넘긴다. */
  uploads: import('@tus/server').Server;
  /** 밖에서 들어온 기기 잠금 (6자리 숫자 → 기기 표). */
  remoteAuth: import('../remote.js').RemoteAuth;
  /** AI 도구가 없을 때 마디가 대신 깔아 주는 것. */
  aiInstaller: import('../agent/install.js').AiInstaller;
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

  /**
   * 밖에서 들어온 요청은 짝지은 기기만 통과. 이 PC 에서 직접 연 브라우저는 늘 통과.
   * 화면(정적 파일)은 막지 않는다 — 폰이 숫자 넣는 화면을 봐야 하니까.
   */
  const allowed = (c: Context): boolean => {
    const { incoming } = c.env as unknown as HttpBindings;
    if (isDirectRequest(incoming.socket?.remoteAddress, incoming.headers)) return true;
    return deps.remoteAuth.has(readCookie(c.req.header('cookie'), PAIR_COOKIE));
  };
  app.use('/api/*', async (c, next) => {
    // 숫자를 넣는 곳 자체는 열려 있어야 한다
    if (c.req.path === '/api/remote/pair') return next();
    if (allowed(c)) return next();
    return c.json({ error: { code: 'needs_pair', message: 'pair with the 6-digit code' } }, 401);
  });
  // 영상 파일과 실시간 알림도 같이 막는다
  app.use('/media/*', async (c, next) => (allowed(c) ? next() : c.text('needs_pair', 401)));
  app.use('/ws', async (c, next) => (allowed(c) ? next() : c.text('needs_pair', 401)));

  // ---- 밖에서 접속하기 ----
  app.get('/api/remote', (c) => {
    const { incoming } = c.env as unknown as HttpBindings;
    const direct = isDirectRequest(incoming.socket?.remoteAddress, incoming.headers);
    const s = settings.get();
    const body: RemoteResponse = {
      mode: s.remoteMode,
      status: deps.tunnel.state.status,
      url: deps.tunnel.state.url,
      error: deps.tunnel.state.error,
      // 숫자는 이 PC 화면에서만 보여 준다
      pin: direct && s.remoteMode !== 'off' ? deps.remoteAuth.currentPin : null,
      devices: deps.remoteAuth.deviceCount,
    };
    return c.json(body);
  });

  /** 폰이 6자리 숫자를 넣는 곳. 맞으면 이 기기 표를 쿠키로 준다. */
  app.post('/api/remote/pair', async (c) => {
    if (settings.get().remoteMode === 'off') return c.json({ error: { code: 'remote_off', message: 'remote access is off' } }, 409);
    const parsed = PairRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_pin', message: 'bad pin' } }, 400);
    const token = deps.remoteAuth.pair(parsed.data.pin);
    if (!token) return c.json({ error: { code: 'bad_pin', message: 'wrong pin' } }, 403);
    // 터널은 https 라 Secure 를 붙여도 되지만, 개발 중 http 로도 짝지을 수 있어야 해서 붙이지 않는다.
    c.header('set-cookie', `${PAIR_COOKIE}=${token}; Path=/; Max-Age=${60 * 60 * 24 * 365}; SameSite=Lax; HttpOnly`);
    deps.events.record('remote.paired');
    const body: PairResponse = { ok: true };
    return c.json(body);
  });

  app.get('/api/health', async (c) => {
    const ai = await deps.agent.status();
    const u = deps.update.state;
    const body: HealthResponse = {
      ok: true,
      version: deps.version,
      update: { available: u.available, downloaded: u.downloaded, canInstall: u.canInstall },
      ai,
      tunnel: { status: deps.tunnel.state.status, error: deps.tunnel.state.error, url: deps.tunnel.state.url },
    };
    return c.json(body);
  });

  // 새 버전: 상태 · 지금 확인 · 받아 둔 것으로 다시 시작. 개발 모드(훅 없음)면 확인 · 설치는 409.
  app.get('/api/update', (c) => {
    const body: UpdateResponse = { update: deps.update.state };
    return c.json(body);
  });
  app.post('/api/update/check', async (c) => {
    if (!(await deps.update.check())) return c.json({ error: { code: 'update_unavailable', message: 'not a packaged app' } }, 409);
    const body: UpdateResponse = { update: deps.update.state };
    return c.json(body);
  });
  app.post('/api/update/install', (c) => {
    if (!deps.update.install()) return c.json({ error: { code: 'update_not_ready', message: 'no downloaded update' } }, 409);
    deps.events.record('update.install', { to: deps.update.state.available });
    const body: UpdateResponse = { update: deps.update.state };
    return c.json(body);
  });

  const AI_LABELS = { claude: 'Claude Code', codex: 'Codex' } as const;

  /** 한 도구를 이 PC 에서 찾아 본다. 사용자가 직접 골라 준 파일이 있으면 그것부터. */
  const lookUpProvider = async (id: 'claude' | 'codex', fresh: boolean): Promise<AiProviderInfo> => {
    const info = await detectCli(id, { fresh, custom: settings.get().ai.paths?.[id] ?? null });
    return {
      id,
      label: AI_LABELS[id],
      installed: info.installed,
      version: info.version,
      path: info.path,
      custom: info.custom,
      canInstall: deps.aiInstaller.canInstall(id),
      installLine: installLine(id),
    };
  };

  const bothProviders = async (fresh: boolean) => Promise.all([lookUpProvider('claude', fresh), lookUpProvider('codex', fresh)]);

  /** 설치 여부. `?fresh=1` 이면 캐시를 버리고 처음부터 다시 찾는다 (화면의 "다시 찾기"). */
  app.get('/api/ai/providers', async (c) => {
    const fresh = c.req.query('fresh') === '1';
    const body: AiProvidersResponse = { providers: await bothProviders(fresh) };
    return c.json(body);
  });

  /**
   * 설치 위치는 PC 마다 다르다. 못 찾으면 사용자가 실행 파일을 직접 알려 준다.
   * 진짜 그 도구인지 한 번 실행해 보고, 되면 설정에 남긴다. path 가 null 이면 직접 고른 것을 지운다.
   */
  app.post('/api/ai/path', async (c) => {
    const parsed = AiPathRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: 'provider and path required' } }, 400);
    const { provider, path: picked } = parsed.data;
    if (picked && !(await cliVersion(picked))) {
      return c.json({ error: { code: 'ai_path_bad', message: 'that file did not run' } }, 400);
    }
    const now = settings.get().ai;
    settings.patch({ ai: { ...now, paths: { ...now.paths, [provider]: picked } } });
    deps.onSettingsChanged?.();
    deps.events.record('ai.path.set', { provider, cleared: picked === null });
    const body: AiProvidersResponse = { providers: await bothProviders(true) };
    return c.json(body);
  });

  /** 트레이 앱의 파일 선택창으로 실행 파일 고르기. 고른 파일이 안 돌면 400 ai_path_bad. */
  app.post('/api/ai/pick', async (c) => {
    const parsed = AiPathRequest.pick({ provider: true }).safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: 'provider required' } }, 400);
    if (!deps.pickFile) return c.json({ error: { code: 'no_picker', message: 'file picker unavailable' } }, 501);
    const picked = await deps.pickFile();
    if (!picked) {
      const body: AiPickResponse = { canceled: true, provider: null };
      return c.json(body);
    }
    if (!(await cliVersion(picked))) return c.json({ error: { code: 'ai_path_bad', message: 'that file did not run' } }, 400);
    const id = parsed.data.provider;
    const now = settings.get().ai;
    settings.patch({ ai: { ...now, paths: { ...now.paths, [id]: picked } } });
    deps.onSettingsChanged?.();
    deps.events.record('ai.path.set', { provider: id, picked: true });
    const body: AiPickResponse = { canceled: false, provider: await lookUpProvider(id, true) };
    return c.json(body);
  });

  /**
   * 아예 안 깔린 PC: 마디가 공식 설치기를 대신 돌린다 (node·관리자 권한 필요 없음).
   * 상태를 계속 물어보며 "받는 중 → 다 됐어요"만 보여 준다.
   */
  app.get('/api/ai/install', async (c) => {
    const body: AiInstallResponse = { install: deps.aiInstaller.state, providers: await bothProviders(deps.aiInstaller.state.status === 'done') };
    return c.json(body);
  });

  app.post('/api/ai/install', async (c) => {
    const parsed = AiInstallRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: 'provider required' } }, 400);
    const id = parsed.data.provider;
    if (!deps.aiInstaller.canInstall(id)) return c.json({ error: { code: 'ai_install_unsupported', message: 'no installer for this OS' } }, 501);
    if (!deps.aiInstaller.start(id)) return c.json({ error: { code: 'ai_install_busy', message: 'already installing' } }, 409);
    deps.events.record('ai.install.start', { provider: id });
    const body: AiInstallResponse = { install: deps.aiInstaller.state, providers: await bothProviders(false) };
    return c.json(body);
  });

  /** 오류를 닫을 때 (다음 시도를 위해 비운다). */
  app.delete('/api/ai/install', async (c) => {
    deps.aiInstaller.clear();
    const body: AiInstallResponse = { install: deps.aiInstaller.state, providers: await bothProviders(false) };
    return c.json(body);
  });

  /** 로그인 창(터미널) 열기. 거기서 브라우저가 열리고 구독 계정으로 로그인한다. */
  app.post('/api/ai/login', async (c) => {
    const parsed = AiInstallRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: 'provider required' } }, 400);
    const plan = loginPlan(parsed.data.provider);
    if (!plan) return c.json({ error: { code: 'ai_login_unsupported', message: 'cannot open a terminal here' } }, 501);
    try {
      const child = spawn(plan.command, plan.args, { stdio: 'ignore', detached: true, windowsHide: false });
      child.unref();
    } catch (err) {
      return c.json({ error: { code: 'ai_login_failed', message: err instanceof Error ? err.message : String(err) } }, 500);
    }
    deps.events.record('ai.login.open', { provider: parsed.data.provider });
    return c.json({ opened: true });
  });

  // 버튼 액션 · 인사 · 자동 편집안이 같이 쓰는 것. AI 는 "골라져 있는지"만 본다 (설치 확인은 잡이 돌 때).
  const actionDeps = { queue, videos, library: deps.library, events: deps.events, plans: deps.plans, aiOn: () => settings.get().ai.provider !== 'none', contextKey: (video: Video) => deps.styleService.contextKey(video), subtitleStyle: () => deps.styleService.response().subtitleStyle };

  app.get('/api/videos', (c) => {
    const body: VideosResponse = { videos: videos.listVisible().map((v) => toCard(v, deps)) };
    return c.json(body);
  });

  app.get('/api/videos/:id', (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    if (v.status === 'ready') greetIfEmpty(actionDeps, v);
    const body: VideoDetailResponse = {
      video: toCard(v, deps),
      transcript: deps.library.transcriptOf(v.id),
      outputs: deps.library.outputsOf(v.id).map((o) => toOutputCard(o, cfg)),
      messages: deps.library.messagesOf(v.id),
      jobs: queue.list(['queued', 'running']).filter((j) => j.videoId === v.id),
      aiBusy: deps.agent.isBusy(v.id),
      chapters: deps.chapters.get(v.id),
      plan: deps.plans.get(v.id),
    };
    return c.json(body);
  });

  // 편집안 후보에 판단 남기기 — 빼기 · 되돌리기 (기획안 §9). 같은 종류를 반복해서 빼면 기억으로 제안한다.
  app.post('/api/videos/:id/plan/feedback', async (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    const parsed = PlanFeedbackRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    const before = deps.plans.get(v.id);
    if (!before) return c.json({ error: { code: 'plan_missing', message: 'no plan' } }, 409);
    const wasRejected = planRejected(before, parsed.data.kind, parsed.data.index);
    const plan = deps.plans.setFeedback(v.id, parsed.data);
    if (!plan) return c.json({ error: { code: 'not_found', message: 'candidate not found' } }, 404);
    const cutKind = parsed.data.kind === 'cut' ? before.cutCandidates[parsed.data.index]?.kind : undefined;
    deps.events.record('plan.feedback', { kind: parsed.data.kind, verdict: parsed.data.verdict, ...(cutKind ? { cutKind } : {}) });
    if (parsed.data.verdict === 'rejected' && !wasRejected && cutKind) {
      const text = rejectionMemory(cutKind, deps.plans.bumpRejected(cutKind));
      if (text) deps.memory.add({ text, kind: 'keep', scope: 'all', source: 'feedback', status: 'proposed' });
    }
    const body: PlanResponse = { plan };
    return c.json(body);
  });

  // AI 연결 뒤의 채팅. 미연결이면 러너를 스폰하지 않는다 (409 ai_off).
  app.post('/api/videos/:id/chat', async (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    if (v.status !== 'ready') return c.json({ error: { code: 'video_not_ready', message: 'video not ready' } }, 409);
    const parsed = ChatRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    const target = parsed.data.editId ? deps.library.edit(parsed.data.editId) : null;
    if (parsed.data.editId && (!target || target.videoId !== v.id)) return c.json({ error: { code: 'bad_request', message: 'edit not found for video' } }, 400);
    try {
      const body: ChatResponse = { messages: deps.agent.ask(v, parsed.data.text, parsed.data.editId) };
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

  /** 자막 직접 쓰기/고치기: 자막 전체를 준 줄들로 바꾼다 (소리 없는 영상도). 바뀐 줄은 단어 시각이 없고, 그대로인 줄은 유지. */
  app.put('/api/videos/:id/transcript', async (c) => {
    const video = deps.videos.get(c.req.param('id'));
    if (!video) return c.notFound();
    const parsed = TranscriptPutRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    const target = parsed.data.editId ? deps.library.edit(parsed.data.editId) : null;
    if (parsed.data.editId && (!target || target.videoId !== video.id)) return c.json({ error: { code: 'not_found', message: 'edit not found' } }, 404);
    if (parsed.data.segments.some((s) => video.durationSec !== null && s.end > video.durationSec)) return c.json({ error: { code: 'bad_request', message: 'subtitle outside video' } }, 400);
    // 원본 자막을 빈 버전으로 덮으면 "자막 만들기"가 자막이 있다고 보고 음성 인식을 다시 안 돌린다 → 결과물 자막을 뺄 때(editId)만 빈 목록을 받는다
    if (parsed.data.segments.length === 0 && !target) return c.json({ error: { code: 'bad_request', message: 'no subtitle lines' } }, 400);
    const existing = target ? deps.library.transcriptForEdit(target) : deps.library.transcriptOf(video.id);
    const fresh = mergeSubtitleLines([], parsed.data.segments, true);
    const segments = fresh.map((seg) => {
      const same = existing?.segments.find((o) => o.text === seg.text && o.secondaryText === seg.secondaryText && Math.abs(o.start - seg.start) < 0.05 && Math.abs(o.end - seg.end) < 0.05);
      return same ?? seg;
    });
    // 고친 말을 남긴다 (틀린 말 → 바른 말) — 다음 자막부터 알려 주고, 반복되면 바로 바꾼다 (기획안 §5.2)
    const pairs = existing ? diffCorrections(existing.segments, segments) : [];
    if (pairs.length) deps.corrections.record(pairs, video.id);
    const transcript = deps.library.setTranscript(video.id, { language: existing?.language ?? 'ko', model: 'manual', segments }, { source: !target });
    deps.events.record('transcript.edited', { lines: segments.length, manual: true, total: segments.length, corrections: pairs.length });
    const body: TranscriptResponse = { transcript };
    return c.json(body);
  });

  app.post('/api/videos/:id/actions', async (c) => {
    const v = videos.get(c.req.param('id'));
    if (!v) return c.json({ error: { code: 'not_found', message: 'video not found' } }, 404);
    const parsed = ActionRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    try {
      const body: ActionResponse = runAction(actionDeps, v, parsed.data);
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
    // 고쳐서 만든 결과물이면 고치기 전 것도 같이 (기획안 §6 수정안 비교)
    const prevEdit = edit.revisionOf ? deps.library.edit(edit.revisionOf) : null;
    const prevOut = prevEdit ? deps.library.outputsForEdit(prevEdit.id)[0] : undefined;
    const body: OutputDetailResponse = {
      output: toOutputCard(o, cfg),
      edit,
      transcript: deps.library.transcriptForEdit(edit),
      video: toCard(v, deps),
      previous: prevEdit && prevOut ? { output: toOutputCard(prevOut, cfg), edit: prevEdit } : null,
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
    // ai 는 한 겹 더 봐야 한다 — provider 만 보냈는데 paths 가 기본값(null)으로 덮이면 직접 고른 파일이 날아간다
    if (patch.ai) {
      const sentAi = new Set(Object.keys(((raw as { ai?: object } | null)?.ai ?? {}) as object));
      patch.ai = Object.fromEntries(Object.entries(patch.ai).filter(([k]) => sentAi.has(k))) as typeof patch.ai;
    }
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
  app.post('/api/style/relearn', async (c) => {
    await deps.styleService.detectDownloader();
    deps.styleService.refresh({ retryFailed: true });
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 링크로 배우기: 유튜브·틱톡·릴스 주소 → 받아서 완성본으로 분석. */
  app.post('/api/style/links', async (c) => {
    const parsed = AddLinkRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_link', message: parsed.error.message } }, 400);
    try {
      if (!deps.styleService.response().linkImport) await deps.styleService.detectDownloader();
      deps.styleService.addLink(parsed.data.url);
    } catch (err) {
      if (err instanceof LinkError) return c.json({ error: { code: err.code, message: err.code } }, err.code === 'no_downloader' ? 501 : 400);
      throw err;
    }
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 기억 한 줄 빼기 (완성본에서 추린 것 · 편집 중 남긴 것 · 직접 쓴 것 모두). */
  app.delete('/api/style/memory/:id', (c) => {
    if (!deps.memory.remove(c.req.param('id'))) return c.json({ error: { code: 'not_found', message: 'memory not found' } }, 404);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 기억 한 줄 직접 쓰기 (범위 · 종류 포함). 직접 쓴 것은 바로 확인된 것. */
  app.post('/api/style/memory', async (c) => {
    const parsed = RememberRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    deps.memory.add({ ...parsed.data, source: 'user' });
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 기억 한 줄 고치기: 글을 바꾸거나 제안을 확인한다. */
  app.patch('/api/style/memory/:id', async (c) => {
    const parsed = MemoryPatchRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    const id = c.req.param('id');
    if (!deps.memory.get(id)) return c.json({ error: { code: 'not_found', message: 'memory not found' } }, 404);
    if (parsed.data.text !== undefined) deps.memory.updateText(id, parsed.data.text);
    if (parsed.data.status === 'approved') deps.memory.approve([id]);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 제안 확인 — ids 가 없으면 제안 전부. */
  app.post('/api/style/memory/approve', async (c) => {
    const parsed = MemoryApproveRequest.safeParse((await c.req.json().catch(() => null)) ?? {});
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    deps.memory.approve(parsed.data.ids);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 기억 전부 지우기 (?only=proposed 면 제안만). 완성본에서 온 글은 다시 제안하지 않는다. */
  app.delete('/api/style/memory', (c) => {
    deps.memory.removeAll({ onlyProposed: c.req.query('only') === 'proposed' });
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 완성본 하나를 학습에서 빼거나 다시 넣기. */
  /** 고친 말 빼기 — 더는 알려 주지도, 바꾸지도 않는다. */
  app.delete('/api/style/corrections/:id', (c) => {
    if (!deps.corrections.remove(c.req.param('id'))) return c.json({ error: { code: 'not_found', message: 'correction not found' } }, 404);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  app.patch('/api/style/references/:id', async (c) => {
    const parsed = ReferencePatchRequest.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: 'bad_request', message: parsed.error.message } }, 400);
    if (!deps.styleService.setExcluded(c.req.param('id'), parsed.data.excluded)) return c.json({ error: { code: 'not_found', message: 'reference not found' } }, 404);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  /** 완성본 하나 빼기 (링크로 받은 것은 파일도 지운다). */
  app.delete('/api/style/references/:id', (c) => {
    if (!deps.styleService.removeReference(c.req.param('id'))) return c.json({ error: { code: 'not_found', message: 'reference not found' } }, 404);
    const body: StyleResponse = deps.styleService.response();
    return c.json(body);
  });

  // ---- 폰에서 올리기 (tus) — Hono 를 거치지 않고 node req/res 로 직접 ----
  const tus = async (c: import('hono').Context) => {
    const { incoming, outgoing } = c.env as unknown as HttpBindings;
    await deps.uploads.handle(incoming, outgoing);
    return RESPONSE_ALREADY_SENT;
  };
  app.all('/api/uploads', tus);
  app.all('/api/uploads/*', tus);

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
