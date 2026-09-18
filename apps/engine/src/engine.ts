import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { serve, type ServerType } from '@hono/node-server';
import { type EngineConfig, loadConfig } from './config.js';
import { openDb } from './db/index.js';
import { EventLog } from './events.js';
import { createLogger, type Logger } from './log.js';
import { ensureWhisperModel, resolveSidecar, resolveWhisperModel } from './main/sidecar.js';
import { JobQueue } from './queue/index.js';
import { createApp, mountWeb } from './server/app.js';
import { attachWs } from './server/ws.js';
import { SettingsStore } from './settings.js';
import { VideoStore } from './videos.js';
import { FolderWatcher } from './watch/index.js';
import { Ffmpeg } from './workers/ffmpeg.js';
import { registerMediaWorkers } from './workers/index.js';
import { registerEditWorkers } from './workers/edit.js';
import { Whisper } from './workers/whisper.js';
import { Library } from './library.js';
import { Tunnel } from './tunnel.js';
import { RemoteAuth } from './remote.js';
import { AiInstaller } from './agent/install.js';
import { ClaudeProvider } from './agent/claude.js';
import { CodexProvider } from './agent/codex.js';
import { detectCli } from './agent/detect.js';
import { AgentRunner } from './agent/runner.js';
import { StyleProfile } from './agent/style.js';
import { AgentTools } from './agent/tools.js';
import { writeMcpConfig } from './agent/mcp-config.js';
import { ReferenceStore } from './style/references.js';
import { MemoryStore } from './style/memory.js';
import { ChapterStore } from './chapters/store.js';
import { registerChapterWorkers } from './workers/chapters.js';
import { StyleService } from './style/service.js';
import { createUploadServer } from './server/upload.js';

const require = createRequire(import.meta.url);
const VERSION: string = (require('../package.json') as { version: string }).version;

/**
 * 우리 MCP 서버를 띄우는 명령. 에이전트 CLI 가 자식으로 실행한다.
 * 개발: node --import tsx/esm src/mcp/index.ts. 패키징: Electron 을 node 로(ELECTRON_RUN_AS_NODE) mcp.mjs.
 */
export function mcpCommand(cfg: EngineConfig): { command: string; args: string[]; env: Record<string, string> } {
  if (cfg.isDev) {
    const loader = pathToFileURL(require.resolve('tsx/esm')).href;
    return { command: process.execPath, args: ['--import', loader, cfg.mcpEntry], env: {} };
  }
  return { command: process.execPath, args: [cfg.mcpEntry], env: { ELECTRON_RUN_AS_NODE: '1' } };
}

export interface Engine {
  cfg: EngineConfig;
  log: Logger;
  settings: SettingsStore;
  videos: VideoStore;
  queue: JobQueue;
  library: Library;
  tunnel: Tunnel;
  remoteAuth: RemoteAuth;
  watcher: FolderWatcher;
  agent: AgentRunner;
  style: StyleProfile;
  styleService: StyleService;
  refs: ReferenceStore;
  chapters: ChapterStore;
  url: string;
  /** Electron 이 시스템 폴더 선택창을 붙인다. */
  setFolderPicker(fn: (() => Promise<string | null>) | undefined): void;
  /** Electron 이 shell.openPath 를 붙인다 (갤러리의 "폴더 열기"). */
  setFolderOpener(fn: ((dir: string) => Promise<void>) | undefined): void;
  /** Electron 이 파일 선택창을 붙인다 (AI 도구 실행 파일 직접 고르기). */
  setFilePicker(fn: (() => Promise<string | null>) | undefined): void;
  stop(): Promise<void>;
}

/** 엔진 기동. Electron 메인과 headless 개발 진입이 같이 쓴다. */
export async function startEngine(overrides: Partial<EngineConfig> = {}): Promise<Engine> {
  const cfg = loadConfig(overrides);
  const log = createLogger(cfg.logsDir, cfg.isDev);
  const { db, sqlite } = openDb(cfg.dbPath, cfg.migrationsDir);

  const settings = new SettingsStore(db);
  const events = new EventLog(db);
  const videos = new VideoStore(db);
  const queue = new JobQueue(db, log);
  const library = new Library(db);
  const ffmpeg = new Ffmpeg({
    ffmpeg: resolveSidecar('ffmpeg', cfg.binDir),
    ffprobe: resolveSidecar('ffprobe', cfg.binDir),
  });
  registerMediaWorkers({ cfg, queue, videos, ffmpeg, events, log });
  const ffmpegBin = resolveSidecar('ffmpeg', cfg.binDir);
  const whisperBin = resolveSidecar('whisper', cfg.binDir);
  const model = resolveWhisperModel(cfg.modelsDir);
  const whisper = async () => {
    await ensureWhisperModel(model, (r) => log.debug({ r }, 'model download'));
    return new Whisper({ ffmpeg: ffmpegBin, whisper: whisperBin }, model.path);
  };
  const style = new StyleProfile(cfg.styleDir);
  style.ensure();
  registerEditWorkers({ cfg, queue, videos, library, ffmpeg, ffmpegBin, events, log, whisper, style });
  const chapters = new ChapterStore(db);
  registerChapterWorkers({ queue, videos, library, chapters, style, ffmpegBin, events, log });
  const watcher = new FolderWatcher({ videos, queue, events, log });
  const refs = new ReferenceStore(db);
  const memory = new MemoryStore(db);
  const ytdlpBin = resolveSidecar('ytdlp', cfg.binDir);
  const providers = { claude: new ClaudeProvider(writeMcpConfig), codex: new CodexProvider() };
  const styleService = new StyleService({ cfg, settings, refs, queue, videos, library, style, ffmpeg, ffmpegBin, ytdlpBin, whisper, events, log, memory, providers });
  styleService.registerWorker();

  const tunnel = new Tunnel(resolveSidecar('cloudflared', cfg.binDir), log);
  const remoteAuth = new RemoteAuth(path.join(cfg.dataDir, 'pairs.json'));
  const aiInstaller = new AiInstaller(log);
  const url = `http://127.0.0.1:${cfg.port}`;
  let remoteMode = settings.get().remoteMode;
  const tunnelConfig = () => {
    const s = settings.get();
    return { mode: s.remoteMode, token: s.tunnelToken, localUrl: url };
  };
  const agentTools = new AgentTools({ cfg, library, videos, queue, ffmpegBin, style, chapters, events, log, memory });
  const agent = new AgentRunner({
    cfg,
    settings,
    library,
    videos,
    events,
    log,
    style,
    providers,
    mcpCommand: () => mcpCommand(cfg),
    engineUrl: () => url,
    recall: (video) => styleService.recall(video),
  });
  const uploads = createUploadServer({ cfg, settings, events, log });
  const deps = {
    cfg,
    videos,
    queue,
    settings,
    library,
    events,
    tunnel,
    remoteAuth,
    aiInstaller,
    agent,
    uploads,
    agentTools,
    styleService,
    memory,
    chapters,
    version: VERSION,
    onSettingsChanged: () => {
      void watcher.setFolders(settings.get().watchFolders);
      const next = tunnelConfig();
      // 밖에서 접속을 끄면 짝지은 폰도 전부 끊는다. 다시 켜면 숫자가 새로 생긴다.
      if (next.mode === 'off' && remoteMode !== 'off') remoteAuth.forgetAll();
      else if (next.mode !== 'off' && remoteMode === 'off') remoteAuth.resetPin();
      remoteMode = next.mode;
      tunnel.apply(next);
      styleService.refresh();
      const ai = settings.get().ai;
      if (ai.provider !== 'none') void detectCli(ai.provider, { fresh: true, custom: ai.paths?.[ai.provider] ?? null });
    },
    pickFolder: undefined as (() => Promise<string | null>) | undefined,
    pickFile: undefined as (() => Promise<string | null>) | undefined,
    openFolder: undefined as ((dir: string) => Promise<void>) | undefined,
  };
  const app = createApp(deps);
  const ws = attachWs(app, VERSION, log);
  const webMounted = mountWeb(app, cfg);
  videos.on('video.added', (video) => ws.broadcast({ type: 'video.added', video }));
  videos.on('video.updated', (video) => ws.broadcast({ type: 'video.updated', video }));
  videos.on('video.removed', (videoId) => ws.broadcast({ type: 'video.removed', videoId }));
  queue.on('job.updated', (job) => ws.broadcast({ type: 'job.updated', job }));
  library.on('message.added', (message) => ws.broadcast({ type: 'message.added', message }));
  library.on('message.updated', (message) => ws.broadcast({ type: 'message.updated', message }));
  library.on('output.added', (output) => ws.broadcast({ type: 'output.added', output }));
  refs.on('reference.updated', (reference) => ws.broadcast({ type: 'reference.updated', reference }));
  styleService.on('style.updated', () => ws.broadcast({ type: 'style.updated' }));
  memory.on('memory.updated', () => ws.broadcast({ type: 'style.updated' }));

  const server: ServerType = await new Promise((resolve, reject) => {
    const s = serve({ fetch: app.fetch, port: cfg.port, hostname: '127.0.0.1' }, () => resolve(s));
    s.once('error', reject);
  });
  ws.injectWebSocket(server);
  log.info({ url, encoder: await ffmpeg.detectEncoder(), data: cfg.dataDir, web: webMounted ? cfg.webDir : null }, 'engine up');
  events.record('engine.start', { version: VERSION });

  await watcher.setFolders(settings.get().watchFolders);
  tunnel.apply(tunnelConfig());
  styleService.refresh();
  // 링크로 배우기(yt-dlp)가 되는 PC 인지 — 몇 초 걸릴 수 있어 기다리지 않는다
  void styleService.detectDownloader();
  queue.tick();
  // AI 도구 설치 여부는 미리 봐 둔다 (--version 이 몇 초 걸릴 수 있다)
  {
    const ai = settings.get().ai;
    if (ai.provider !== 'none') void detectCli(ai.provider, { custom: ai.paths?.[ai.provider] ?? null });
  }

  return {
    cfg,
    log,
    settings,
    videos,
    queue,
    library,
    tunnel,
    remoteAuth,
    watcher,
    agent,
    style,
    styleService,
    refs,
    chapters,
    url,
    setFolderPicker(fn) {
      deps.pickFolder = fn;
    },
    setFolderOpener(fn) {
      deps.openFolder = fn;
    },
    setFilePicker(fn) {
      deps.pickFile = fn;
    },
    async stop() {
      agent.stopAll();
      aiInstaller.stop();
      styleService.stop();
      tunnel.stop();
      await watcher.stop();
      await queue.stop();
      ws.closeAll();
      await new Promise<void>((r) => {
        server.close(() => r());
        (server as import('node:http').Server).closeAllConnections?.();
      });
      sqlite.close();
    },
  };
}
