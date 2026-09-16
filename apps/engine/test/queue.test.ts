import fs from 'node:fs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { Job } from '@madi/shared';
import { JobQueue } from '../src/queue/index.js';
import { openTestDb, quietLogger, tempHome, waitFor } from './helpers.js';

let home: string;
let queue: JobQueue;
let sqlite: ReturnType<typeof openTestDb>['sqlite'];

beforeEach(() => {
  home = tempHome();
  const opened = openTestDb(home);
  sqlite = opened.sqlite;
  queue = new JobQueue(opened.db, quietLogger(home));
});

afterEach(async () => {
  await queue.stop();
  sqlite.close();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('JobQueue', () => {
  it('핸들러를 돌리고 done 으로 끝낸다', async () => {
    const seen: string[] = [];
    queue.register('probe', async ({ job }) => {
      seen.push(job.videoId!);
    });
    const job = queue.enqueue({ type: 'probe', videoId: 'v1' });
    expect(job.status).toBe('queued');
    await queue.idle();
    expect(seen).toEqual(['v1']);
    expect(queue.get(job.id)?.status).toBe('done');
    expect(queue.get(job.id)?.progress).toBe(1);
  });

  it('렌더는 editId 가 다르면 같은 영상이라도 따로 건다', async () => {
    let calls = 0;
    queue.register('render', async () => {
      calls++;
    });
    const a = queue.enqueue({ type: 'render', videoId: 'v1', editId: 'e1' });
    const b = queue.enqueue({ type: 'render', videoId: 'v1', editId: 'e2' });
    const again = queue.enqueue({ type: 'render', videoId: 'v1', editId: 'e1' });
    expect(b.id).not.toBe(a.id);
    expect(again.id).toBe(a.id);
    await queue.idle();
    expect(calls).toBe(2);
  });

  it('같은 (type, videoId) 는 중복으로 넣지 않는다', async () => {
    let calls = 0;
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    queue.register('proxy', async () => {
      calls++;
      await gate;
    });
    const a = queue.enqueue({ type: 'proxy', videoId: 'v1' });
    const b = queue.enqueue({ type: 'proxy', videoId: 'v1' });
    expect(b.id).toBe(a.id);
    release();
    await queue.idle();
    expect(calls).toBe(1);
  });

  it('타입별 동시성을 지킨다 (proxy=1)', async () => {
    let running = 0;
    let peak = 0;
    queue.register('proxy', async () => {
      running++;
      peak = Math.max(peak, running);
      await new Promise((r) => setTimeout(r, 50));
      running--;
    });
    queue.enqueue({ type: 'proxy', videoId: 'a' });
    queue.enqueue({ type: 'proxy', videoId: 'b' });
    queue.enqueue({ type: 'proxy', videoId: 'c' });
    await queue.idle();
    expect(peak).toBe(1);
  });

  it('실패하면 failed 와 error 를 남기고 이벤트를 낸다', async () => {
    const updates: Job[] = [];
    queue.on('job.updated', (j) => updates.push(j));
    queue.register('thumbnail', async () => {
      throw new Error('boom');
    });
    const job = queue.enqueue({ type: 'thumbnail', videoId: 'v1' });
    await queue.idle();
    const final = queue.get(job.id)!;
    expect(final.status).toBe('failed');
    expect(final.error).toBe('boom');
    expect(updates.some((u) => u.id === job.id && u.status === 'failed')).toBe(true);
  });

  it('진행률을 기록한다', async () => {
    queue.register('proxy', async ({ setProgress }) => {
      setProgress(0.5);
      await new Promise((r) => setTimeout(r, 10));
    });
    const job = queue.enqueue({ type: 'proxy', videoId: 'v1' });
    await waitFor(() => (queue.get(job.id)?.progress ?? 0) >= 0.5);
    await queue.idle();
    expect(queue.get(job.id)?.progress).toBe(1);
  });

  it('activeForVideo 는 실행 중인 잡을 우선한다', async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    queue.register('proxy', async () => {
      await gate;
    });
    queue.register('thumbnail', async () => {});
    const proxy = queue.enqueue({ type: 'proxy', videoId: 'v1' });
    await waitFor(() => queue.get(proxy.id)?.status === 'running');
    expect(queue.activeForVideo('v1')?.type).toBe('proxy');
    release();
    await queue.idle();
    expect(queue.activeForVideo('v1')).toBeNull();
  });
});
