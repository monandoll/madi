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
    this.deps.log.debug({ next, prev: this.folders, hasWatcher: !!this.watcher }, 'setFolders');
    if (sameList(next, this.folders) && this.watcher) return;
    await this.stop();
    this.folders = next;
    if (next.length === 0) {
      this.reconcile();
      return;
    }

    this.watcher = chokidar.watch(next, {
      ignoreInitial: false,
      depth: 3,
      ignored: (p, stats) => (stats?.isFile() ?? false) && !isVideoFile(path.basename(p)),
      awaitWriteFinish: { stabilityThreshold: this.deps.stabilityMs ?? 2000, pollInterval: 200 },
    });
    // 닫힌 watcher 의 늦은 이벤트(awaitWriteFinish 타이머 등)는 버린다.
    const w = this.watcher;
    const live = () => this.watcher === w;
    w.on('add', (p, stats) => live() && this.onAdd(p, stats));
    w.on('change', (p, stats) => live() && this.onAdd(p, stats));
    w.on('unlink', (p) => live() && this.onUnlink(p));
    w.on('error', (err) => this.deps.log.error({ err }, 'watcher error'));
    await new Promise<void>((resolve) => this.watcher!.once('ready', () => resolve()));
    this.deps.log.debug('watcher ready');
    this.reconcile();
    this.deps.log.info({ folders: next }, 'watching');
  }

  async stop(): Promise<void> {
    await this.watcher?.close();
    this.watcher = null;
  }

  /** 테스트/재기동용: 즉시 한 파일을 등록 절차에 태운다. */
  onAdd(p: string, stats?: fs.Stats): void {
    if (!isVideoFile(path.basename(p)) || path.basename(p).startsWith('.')) return;
    if (!this.isWatched(p)) return;
    this.deps.log.debug({ p }, 'onAdd');
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

  /**
   * DB엔 있는데 디스크에 없거나, 지금 감시 폴더 밖에 있는 영상 → missing (갤러리에서 빠짐).
   * 폴더를 다시 넣으면 초기 스캔이 다시 등록하고, 프록시·썸네일이 남아 있으면 그대로 ready.
   */
  private reconcile(): void {
    let n = 0;
    for (const v of this.deps.videos.list()) {
      if (v.status === 'missing') continue;
      if (!fs.existsSync(v.path) || !this.isWatched(v.path)) {
        this.deps.videos.markMissing(v.id);
        n++;
      }
    }
    this.deps.log.debug({ folders: this.folders, marked: n }, 'reconcile');
  }

  private isWatched(p: string): boolean {
    const target = normalize(p);
    return this.folders.some((f) => target.startsWith(normalize(f) + path.sep));
  }
}

function normalize(p: string): string {
  const abs = path.resolve(p);
  return process.platform === 'win32' ? abs.toLowerCase() : abs;
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
