import { createRequire } from 'node:module';
import { serve, type ServerType } from '@hono/node-server';
import { type EngineConfig, loadConfig } from './config.js';
import { openDb } from './db/index.js';
import { EventLog } from './events.js';
import { createLogger, type Logger } from './log.js';
import { resolveSidecar } from './main/sidecar.js';
import { JobQueue } from './queue/index.js';
import { createApp } from './server/app.js';
import { attachWs } from './server/ws.js';
import { SettingsStore } from './settings.js';
import { VideoStore } from './videos.js';
import { FolderWatcher } from './watch/index.js';
import { Ffmpeg } from './workers/ffmpeg.js';
import { registerMediaWorkers } from './workers/index.js';

const require = createRequire(import.meta.url);
const VERSION: string = (require('../package.json') as { version: string }).version;

export interface Engine {
  cfg: EngineConfig;
  log: Logger;
  settings: SettingsStore;
  videos: VideoStore;
  queue: JobQueue;
  watcher: FolderWatcher;
  url: string;
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
  const ffmpeg = new Ffmpeg({
    ffmpeg: resolveSidecar('ffmpeg', cfg.binDir),
    ffprobe: resolveSidecar('ffprobe', cfg.binDir),
  });
  registerMediaWorkers({ cfg, queue, videos, ffmpeg, events, log });
  const watcher = new FolderWatcher({ videos, queue, events, log });

  const app = createApp({
    cfg,
    videos,
    queue,
    settings,
    version: VERSION,
    onSettingsChanged: () => void watcher.setFolders(settings.get().watchFolders),
  });
  const ws = attachWs(app, VERSION);
  videos.on('video.added', (video) => ws.broadcast({ type: 'video.added', video }));
  videos.on('video.updated', (video) => ws.broadcast({ type: 'video.updated', video }));
  videos.on('video.removed', (videoId) => ws.broadcast({ type: 'video.removed', videoId }));
  queue.on('job.updated', (job) => ws.broadcast({ type: 'job.updated', job }));

  const server: ServerType = await new Promise((resolve, reject) => {
    const s = serve({ fetch: app.fetch, port: cfg.port, hostname: '127.0.0.1' }, () => resolve(s));
    s.once('error', reject);
  });
  ws.injectWebSocket(server);
  const url = `http://127.0.0.1:${cfg.port}`;
  log.info({ url, encoder: await ffmpeg.detectEncoder(), data: cfg.dataDir }, 'engine up');
  events.record('engine.start', { version: VERSION });

  await watcher.setFolders(settings.get().watchFolders);
  queue.tick();

  return {
    cfg,
    log,
    settings,
    videos,
    queue,
    watcher,
    url,
    async stop() {
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
