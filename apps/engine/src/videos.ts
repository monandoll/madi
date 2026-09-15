import fs from 'node:fs';
import { EventEmitter } from 'node:events';
import { desc, eq, ne } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import { Video, Proxy, titleFromFileName } from '@madi/shared';
import type { Db } from './db/index.js';
import { proxies, videos } from './db/schema.js';

export interface VideoEvents {
  'video.added': [Video];
  'video.updated': [Video];
  'video.removed': [string];
}

type VideoRow = typeof videos.$inferSelect;
type VideoUpdate = Partial<Omit<VideoRow, 'id' | 'createdAt'>>;

function rowToVideo(row: VideoRow): Video {
  return Video.parse(row);
}

/** videos / proxies 테이블 접근 + 변경 이벤트. */
export class VideoStore extends EventEmitter<VideoEvents> {
  constructor(private readonly db: Db) {
    super();
  }

  /** 전부 (missing 포함). 감시·정리용. */
  list(): Video[] {
    return this.db.select().from(videos).orderBy(desc(videos.recordedAt)).all().map(rowToVideo);
  }

  /** 갤러리에 보이는 것. 파일이 없거나 감시 폴더 밖이면 안 보인다. */
  listVisible(): Video[] {
    return this.db
      .select()
      .from(videos)
      .where(ne(videos.status, 'missing'))
      .orderBy(desc(videos.recordedAt))
      .all()
      .map(rowToVideo);
  }

  get(id: string): Video | null {
    const row = this.db.select().from(videos).where(eq(videos.id, id)).get();
    return row ? rowToVideo(row) : null;
  }

  mustGet(id: string): Video {
    const v = this.get(id);
    if (!v) throw new Error(`video not found: ${id}`);
    return v;
  }

  getByPath(p: string): Video | null {
    const row = this.db.select().from(videos).where(eq(videos.path, p)).get();
    return row ? rowToVideo(row) : null;
  }

  thumbnailPath(id: string): string | null {
    const row = this.db.select({ t: videos.thumbnailPath }).from(videos).where(eq(videos.id, id)).get();
    return row?.t ?? null;
  }

  proxyOf(videoId: string): Proxy | null {
    const row = this.db.select().from(proxies).where(eq(proxies.videoId, videoId)).get();
    return row ? Proxy.parse(row) : null;
  }

  /** 파일을 처음 봤을 때. 같은 경로가 있으면 그 행을 돌려준다. */
  register(input: { path: string; fileName: string; sizeBytes: number; recordedAt: number }): { video: Video; created: boolean } {
    const existing = this.getByPath(input.path);
    const now = Date.now();
    if (existing) {
      const changed = existing.sizeBytes !== input.sizeBytes || existing.recordedAt !== input.recordedAt;
      if (existing.status === 'missing' || changed) {
        // 돌아온 파일이 그대로면 이전 준비 상태를 살린다 (프록시·썸네일 재작업 없음)
        const status =
          changed || existing.durationSec == null ? 'registered' : this.isPrepared(existing.id) ? 'ready' : 'preparing';
        // 내용이 바뀐 파일이면 옛 썸네일·프록시는 더 이상 이 파일 것이 아니다
        if (changed) this.db.delete(proxies).where(eq(proxies.videoId, existing.id)).run();
        const updated = this.update(existing.id, {
          status,
          sizeBytes: input.sizeBytes,
          recordedAt: input.recordedAt,
          error: null,
          ...(changed ? { thumbnailPath: null, durationSec: null } : {}),
        });
        return { video: updated, created: changed };
      }
      return { video: existing, created: false };
    }
    const row: VideoRow = {
      id: nanoid(),
      path: input.path,
      fileName: input.fileName,
      title: titleFromFileName(input.fileName),
      kind: 'long',
      status: 'registered',
      durationSec: null,
      width: null,
      height: null,
      fps: null,
      hasAudio: null,
      sizeBytes: input.sizeBytes,
      recordedAt: input.recordedAt,
      thumbnailPath: null,
      error: null,
      createdAt: now,
      updatedAt: now,
    };
    this.db.insert(videos).values(row).run();
    const video = rowToVideo(row);
    this.emit('video.added', video);
    return { video, created: true };
  }

  update(id: string, patch: VideoUpdate): Video {
    this.db
      .update(videos)
      .set({ ...patch, updatedAt: Date.now() })
      .where(eq(videos.id, id))
      .run();
    const video = this.mustGet(id);
    this.emit('video.updated', video);
    return video;
  }

  setProxy(videoId: string, p: { path: string; width: number; height: number }): void {
    this.db.delete(proxies).where(eq(proxies.videoId, videoId)).run();
    this.db.insert(proxies).values({ id: nanoid(), videoId, ...p, createdAt: Date.now() }).run();
  }

  /** 썸네일과 프록시가 둘 다 있으면 ready. 그 사이 missing 이 됐으면 되살리지 않는다. */
  markReadyIfComplete(videoId: string): void {
    if (this.get(videoId)?.status !== 'preparing') return;
    const thumb = this.thumbnailPath(videoId);
    const proxy = this.proxyOf(videoId);
    if (thumb && proxy && fs.existsSync(thumb) && fs.existsSync(proxy.path)) {
      this.update(videoId, { status: 'ready', error: null });
    }
  }

  markMissing(id: string): void {
    const v = this.get(id);
    if (v && v.status !== 'missing') this.update(id, { status: 'missing' });
  }

  /** 프록시·썸네일이 이미 있는지 (재기동 시 재작업 방지). */
  isPrepared(id: string): boolean {
    const thumb = this.thumbnailPath(id);
    const proxy = this.proxyOf(id);
    return !!thumb && !!proxy && fs.existsSync(thumb) && fs.existsSync(proxy.path);
  }
}
