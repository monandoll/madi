import fs from 'node:fs';
import path from 'node:path';
import chokidar, { type FSWatcher } from 'chokidar';
import { isVideoFile } from '@madi/shared';
import type { EventLog } from '../events.js';
import type { Logger } from '../log.js';
import type { JobQueue } from '../queue/index.js';
import type { VideoStore } from '../videos.js';

export interface WatcherDeps {
  videos: VideoStore;
  queue: JobQueue;
  events: EventLog;
  log: Logger;
  /** 파일 크기가 이만큼(ms) 변하지 않아야 "다 복사됐다"고 본다 */
  stabilityMs?: number;
}

/**
 * 감시 폴더의 영상 파일 → VideoStore 등록 → probe 잡.
 * 복사 중인 파일은 크기가 안정될 때까지 기다린다.
 */
export class FolderWatcher {
  private watcher: FSWatcher | null = null;
  private folders: string[] = [];

  constructor(private readonly deps: WatcherDeps) {}

  async setFolders(folders: string[]): Promise<void> {
    const next = folders.filter((f) => fs.existsSync(f)).map((f) => path.resolve(f));
    if (sameList(next, this.folders) && this.watcher) return;
    await this.stop();
    this.folders = next;
    if (next.length === 0) return;

    this.watcher = chokidar.watch(next, {
      ignoreInitial: false,
      depth: 3,
      ignored: (p, stats) => (stats?.isFile() ?? false) && !isVideoFile(path.basename(p)),
      awaitWriteFinish: { stabilityThreshold: this.deps.stabilityMs ?? 2000, pollInterval: 200 },
    });
    this.watcher.on('add', (p, stats) => this.onAdd(p, stats));
    this.watcher.on('change', (p, stats) => this.onAdd(p, stats));
    this.watcher.on('unlink', (p) => this.onUnlink(p));
    this.watcher.on('error', (err) => this.deps.log.error({ err }, 'watcher error'));
    await new Promise<void>((resolve) => this.watcher!.once('ready', () => resolve()));
    this.reconcileMissing();
    this.deps.log.info({ folders: next }, 'watching');
  }

  async stop(): Promise<void> {
    await this.watcher?.close();
    this.watcher = null;
  }

  /** 테스트/재기동용: 즉시 한 파일을 등록 절차에 태운다. */
  onAdd(p: string, stats?: fs.Stats): void {
    if (!isVideoFile(path.basename(p)) || path.basename(p).startsWith('.')) return;
    const st = stats ?? safeStat(p);
    if (!st || st.size === 0) return;
    const { video, created } = this.deps.videos.register({
      path: p,
      fileName: path.basename(p),
      sizeBytes: st.size,
      recordedAt: Math.round(st.mtimeMs),
    });
    if (created || video.status === 'registered' || video.status === 'failed' && video.error === 'ffmpeg_missing') {
      this.deps.events.record('video.registered', { ext: path.extname(p).toLowerCase() });
      this.deps.queue.enqueue({ type: 'probe', videoId: video.id });
    } else if (video.status === 'preparing' || (video.status === 'ready' && !this.deps.videos.isPrepared(video.id))) {
      // 재기동: 메타는 있는데 프록시/썸네일이 없다 → 그 단계부터
      this.deps.queue.enqueue({ type: 'thumbnail', videoId: video.id });
      this.deps.queue.enqueue({ type: 'proxy', videoId: video.id });
    }
  }

  private onUnlink(p: string): void {
    const v = this.deps.videos.getByPath(p);
    if (v) {
      this.deps.videos.markMissing(v.id);
      this.deps.log.info({ video: v.id }, 'file gone');
    }
  }

  /** DB엔 있는데 디스크에 없는 파일 → missing. */
  private reconcileMissing(): void {
    for (const v of this.deps.videos.list()) {
      if (v.status !== 'missing' && !fs.existsSync(v.path)) this.deps.videos.markMissing(v.id);
    }
  }
}

function safeStat(p: string): fs.Stats | null {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
}

function sameList(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}
