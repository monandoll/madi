import { EventEmitter } from 'node:events';
import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { nanoid } from 'nanoid';
import { JOB_CONCURRENCY, Job, type JobPayload, type JobType } from '@madi/shared';
import type { Db } from '../db/index.js';
import { jobs } from '../db/schema.js';
import type { Logger } from '../log.js';

export interface JobContext {
  job: Job;
  signal: AbortSignal;
  setProgress(ratio: number): void;
}

export type JobHandler = (ctx: JobContext) => Promise<void>;

export interface QueueEvents {
  'job.updated': [Job];
}

function rowToJob(row: typeof jobs.$inferSelect): Job {
  return Job.parse({ ...row, payload: row.payload });
}

/**
 * SQLite 테이블 하나로 된 인프로세스 큐.
 * - 타입별 동시성은 JOB_CONCURRENCY.
 * - 같은 (type, videoId) 가 이미 대기/실행 중이면 중복으로 넣지 않는다.
 * - 프로세스가 죽었다 살아나면 'running' 을 'queued' 로 되돌린다.
 */
export class JobQueue extends EventEmitter<QueueEvents> {
  private readonly handlers = new Map<JobType, JobHandler>();
  private readonly running = new Map<string, AbortController>();
  private ticking = false;
  private stopped = false;

  constructor(
    private readonly db: Db,
    private readonly log: Logger,
  ) {
    super();
    this.db
      .update(jobs)
      .set({ status: 'queued', progress: 0, startedAt: null })
      .where(eq(jobs.status, 'running'))
      .run();
  }

  register(type: JobType, handler: JobHandler): void {
    this.handlers.set(type, handler);
  }

  enqueue(payload: JobPayload): Job {
    const videoId = 'videoId' in payload ? payload.videoId : null;
    if (videoId) {
      // 같은 영상에 같은 종류의 잡이 이미 걸려 있으면 그것을 돌려준다.
      // 렌더는 편집(editId)마다 다른 결과물이라 editId 까지 같아야 중복이다 (숏폼 여러 개 = 렌더 여러 개).
      const editId = 'editId' in payload ? payload.editId : null;
      const dup = this.db
        .select()
        .from(jobs)
        .where(and(eq(jobs.type, payload.type), eq(jobs.videoId, videoId), inArray(jobs.status, ['queued', 'running'])))
        .all()
        .find((row) => editId === null || (row.payload as { editId?: string }).editId === editId);
      if (dup) return rowToJob(dup);
    }
    const row: typeof jobs.$inferInsert = {
      id: nanoid(),
      type: payload.type,
      status: 'queued',
      progress: 0,
      videoId,
      payload,
      error: null,
      attempts: 0,
      createdAt: Date.now(),
      startedAt: null,
      finishedAt: null,
    };
    this.db.insert(jobs).values(row).run();
    const job = rowToJob(row as typeof jobs.$inferSelect);
    this.emit('job.updated', job);
    queueMicrotask(() => this.tick());
    return job;
  }

  get(id: string): Job | null {
    const row = this.db.select().from(jobs).where(eq(jobs.id, id)).get();
    return row ? rowToJob(row) : null;
  }

  list(statuses?: Job['status'][]): Job[] {
    const q = this.db.select().from(jobs);
    const rows = statuses ? q.where(inArray(jobs.status, statuses)).all() : q.all();
    return rows.map(rowToJob);
  }

  /** 영상 하나에 대해 지금 돌고 있거나 대기 중인 잡 (갤러리 배지용). */
  activeForVideo(videoId: string): Job | null {
    const row = this.db
      .select()
      .from(jobs)
      .where(and(eq(jobs.videoId, videoId), inArray(jobs.status, ['running', 'queued'])))
      .orderBy(sql`case ${jobs.status} when 'running' then 0 else 1 end`, asc(jobs.createdAt))
      .get();
    return row ? rowToJob(row) : null;
  }

  cancel(id: string): void {
    this.running.get(id)?.abort();
    this.db
      .update(jobs)
      .set({ status: 'canceled', finishedAt: Date.now() })
      .where(and(eq(jobs.id, id), eq(jobs.status, 'queued')))
      .run();
    const job = this.get(id);
    if (job) this.emit('job.updated', job);
  }

  async stop(): Promise<void> {
    this.stopped = true;
    for (const ctrl of this.running.values()) ctrl.abort();
    while (this.running.size > 0) await new Promise((r) => setTimeout(r, 20));
  }

  /** 실행 중인 게 없어질 때까지 기다린다 (테스트용). */
  async idle(): Promise<void> {
    for (;;) {
      const pending = this.db
        .select({ n: sql<number>`count(*)` })
        .from(jobs)
        .where(inArray(jobs.status, ['queued', 'running']))
        .get();
      if (!pending || pending.n === 0) return;
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  tick(): void {
    if (this.ticking || this.stopped) return;
    this.ticking = true;
    try {
      for (const [type, limit] of Object.entries(JOB_CONCURRENCY) as [JobType, number][]) {
        if (!this.handlers.has(type)) continue;
        const runningOfType = [...this.running.keys()].filter((id) => this.get(id)?.type === type).length;
        for (let i = runningOfType; i < limit; i++) {
          const claimed = this.claim(type);
          if (!claimed) break;
          void this.run(claimed);
        }
      }
    } finally {
      this.ticking = false;
    }
  }

  private claim(type: JobType): Job | null {
    const now = Date.now();
    const row = this.db.transaction((tx) => {
      const next = tx
        .select()
        .from(jobs)
        .where(and(eq(jobs.type, type), eq(jobs.status, 'queued')))
        .orderBy(asc(jobs.createdAt))
        .get();
      if (!next) return null;
      tx.update(jobs)
        .set({ status: 'running', startedAt: now, attempts: next.attempts + 1 })
        .where(eq(jobs.id, next.id))
        .run();
      return { ...next, status: 'running' as const, startedAt: now, attempts: next.attempts + 1 };
    });
    return row ? rowToJob(row) : null;
  }

  private async run(job: Job): Promise<void> {
    const handler = this.handlers.get(job.type);
    if (!handler) return;
    const ctrl = new AbortController();
    this.running.set(job.id, ctrl);
    this.emit('job.updated', job);
    const started = Date.now();
    let lastEmitted = 0;
    const ctx: JobContext = {
      job,
      signal: ctrl.signal,
      setProgress: (ratio) => {
        const p = Math.max(0, Math.min(1, ratio));
        this.db.update(jobs).set({ progress: p }).where(eq(jobs.id, job.id)).run();
        // 진행 이벤트는 200ms에 한 번만 (WS 폭주 방지)
        const now = Date.now();
        if (now - lastEmitted > 200 || p >= 1) {
          lastEmitted = now;
          this.emit('job.updated', { ...job, progress: p });
        }
      },
    };
    try {
      await handler(ctx);
      this.db
        .update(jobs)
        .set({ status: 'done', progress: 1, finishedAt: Date.now() })
        .where(eq(jobs.id, job.id))
        .run();
      this.log.info({ job: job.id, type: job.type, ms: Date.now() - started }, 'job done');
    } catch (err) {
      const canceled = ctrl.signal.aborted;
      const message = err instanceof Error ? err.message : String(err);
      this.db
        .update(jobs)
        .set({ status: canceled ? 'canceled' : 'failed', error: canceled ? null : message, finishedAt: Date.now() })
        .where(eq(jobs.id, job.id))
        .run();
      if (!canceled) this.log.error({ job: job.id, type: job.type, err: message }, 'job failed');
    } finally {
      this.running.delete(job.id);
      const final = this.get(job.id);
      if (final) this.emit('job.updated', final);
      queueMicrotask(() => this.tick());
    }
  }
}
