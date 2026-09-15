/**
 * 엔진 e2e: 진짜 서버 + 진짜 ffmpeg.
 * 감시 폴더에 샘플을 넣으면 → 등록 → probe → 썸네일·프록시 → ready 가 API/WS/미디어로 보이는지.
 */
import fs from 'node:fs';
import path from 'node:path';
import WebSocket from 'ws';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { VideosResponse, WsEvent } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { SAMPLE_5S, SAMPLE_SILENT, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let watchDir: string;
let engine: Engine;
const wsEvents: WsEvent[] = [];
let ws: WebSocket;

beforeAll(async () => {
  home = tempHome('madi-e2e-');
  watchDir = path.join(home, 'videos');
  fs.mkdirSync(watchDir);
  process.env['MADI_QUIET'] = '1';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });

  ws = new WebSocket(`${engine.url.replace('http', 'ws')}/ws`);
  ws.on('message', (data) => wsEvents.push(WsEvent.parse(JSON.parse(String(data)))));
  await new Promise<void>((resolve, reject) => {
    ws.on('open', () => resolve());
    ws.on('error', reject);
  });
});

afterAll(async () => {
  ws?.close();
  await engine?.stop();
  if (process.env['MADI_E2E_KEEP_LOG']) fs.copyFileSync(path.join(home, 'logs', 'engine.log'), process.env['MADI_E2E_KEEP_LOG']);
  fs.rmSync(home, { recursive: true, force: true });
});

const api = async <T>(p: string, init?: RequestInit): Promise<T> => {
  const res = await fetch(`${engine.url}${p}`, init);
  if (!res.ok) throw new Error(`${p} → ${res.status}`);
  return (await res.json()) as T;
};

describe('engine e2e', () => {
  it('health 는 버전과 AI 미연결을 돌려준다', async () => {
    const h = await api<{ ok: true; version: string; ai: { connected: boolean } }>('/api/health');
    expect(h.ok).toBe(true);
    expect(h.ai.connected).toBe(false);
  });

  it('설정을 바꾸면 감시가 시작되고, 폴더에 넣은 영상이 ready 가 된다', async () => {
    // 감시 전에 하나 미리 두고, 감시 시작 후 하나 더 복사 (초기 스캔 + 실시간 둘 다)
    fs.copyFileSync(SAMPLE_SILENT, path.join(watchDir, '거북목 교정.mp4'));
    await api('/api/settings', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ workspaceName: '수현쌤 스튜디오', watchFolders: [watchDir] }),
    });
    await new Promise((r) => setTimeout(r, 300));
    fs.copyFileSync(SAMPLE_5S, path.join(watchDir, '햄스트링 패시브 스트레칭 풀버전.mp4'));

    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return videos.length === 2 && videos.every((v) => v.status === 'ready');
    }, 60_000);

    const { videos } = VideosResponse.parse(await api('/api/videos'));
    const long = videos.find((v) => v.title === '햄스트링 패시브 스트레칭 풀버전')!;
    expect(long.kind).toBe('short'); // 5초짜리라 숏폼
    expect(long.hasAudio).toBe(true);
    expect(long.durationSec).toBeGreaterThan(4.5);
    expect(long.thumbnailUrl).toMatch(/^\/media\/thumbs\/.+\.jpg/);
    expect(long.proxyUrl).toMatch(/^\/media\/proxies\/.+\.mp4$/);
    expect(long.activeJob).toBeNull();

    const silent = videos.find((v) => v.title === '거북목 교정')!;
    expect(silent.hasAudio).toBe(false);
  });

  it('썸네일과 프록시를 서빙한다 (Range 포함)', async () => {
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    const v = videos[0]!;
    const thumb = await fetch(`${engine.url}${v.thumbnailUrl}`);
    expect(thumb.status).toBe(200);
    expect(thumb.headers.get('content-type')).toBe('image/jpeg');
    expect((await thumb.arrayBuffer()).byteLength).toBeGreaterThan(1000);

    const head = await fetch(`${engine.url}${v.proxyUrl}`, { method: 'HEAD' });
    expect(head.status).toBe(200);
    expect(head.headers.get('accept-ranges')).toBe('bytes');
    const total = Number(head.headers.get('content-length'));

    const part = await fetch(`${engine.url}${v.proxyUrl}`, { headers: { range: 'bytes=0-99' } });
    expect(part.status).toBe(206);
    expect(part.headers.get('content-range')).toBe(`bytes 0-99/${total}`);
    expect((await part.arrayBuffer()).byteLength).toBe(100);

    // 경로 탈출·모르는 id 는 404 (SPA fallback 이 index.html 을 주면 안 된다)
    const traversal = await fetch(`${engine.url}/media/proxies/..%2F..%2Fetc%2Fpasswd`);
    expect(traversal.status).toBe(404);
    const unknown = await fetch(`${engine.url}/media/proxies/nope.mp4`);
    expect(unknown.status).toBe(404);
    const notMedia = await fetch(`${engine.url}/media/proxies/${v.id}.txt`);
    expect(notMedia.status).toBe(404);
  });

  it('WS 로 video/job 이벤트가 왔다', async () => {
    await waitFor(() => wsEvents.some((e) => e.type === 'hello'));
    expect(wsEvents.some((e) => e.type === 'video.added')).toBe(true);
    expect(wsEvents.some((e) => e.type === 'video.updated' && e.video.status === 'ready')).toBe(true);
    expect(wsEvents.some((e) => e.type === 'job.updated' && e.job.type === 'proxy' && e.job.status === 'done')).toBe(true);
  });

  it('파일이 사라지면 갤러리에서 빠지고, 다시 오면 ready 로 돌아온다', async () => {
    const target = path.join(watchDir, '거북목 교정.mp4');
    fs.rmSync(target);
    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return !videos.some((v) => v.title === '거북목 교정');
    });
    expect(engine.videos.list().find((v) => v.title === '거북목 교정')?.status).toBe('missing');
    fs.copyFileSync(SAMPLE_SILENT, target);
    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return videos.find((v) => v.title === '거북목 교정')?.status === 'ready';
    }, 60_000);
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    expect(videos.filter((v) => v.title === '거북목 교정')).toHaveLength(1);
  });

  it('감시 폴더를 바꾸면 이전 폴더 영상은 갤러리에서 빠지고, 되돌리면 다시 만들지 않고 돌아온다', async () => {
    const other = path.join(home, 'other');
    fs.mkdirSync(other);
    const jobsBefore = engine.queue.list().length;
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ watchFolders: [other] }) });
    await waitFor(async () => VideosResponse.parse(await api('/api/videos')).videos.length === 0);

    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ watchFolders: [watchDir] }) });
    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return videos.length === 2 && videos.every((v) => v.status === 'ready');
    });
    await engine.queue.idle();
    expect(engine.queue.list().length).toBe(jobsBefore);
  });

  it('영상이 아닌 파일은 무시하고, 깨진 영상은 failed 로 표시한다', async () => {
    fs.writeFileSync(path.join(watchDir, '메모.txt'), 'hi');
    fs.writeFileSync(path.join(watchDir, '깨진 파일.mp4'), Buffer.alloc(4096, 1));
    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return videos.find((v) => v.title === '깨진 파일')?.status === 'failed';
    });
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    expect(videos.find((v) => v.title === '메모')).toBeUndefined();
    expect(videos.find((v) => v.title === '깨진 파일')?.error).toBeTruthy();
  });

  it('재기동해도 준비된 영상은 다시 만들지 않는다', async () => {
    const jobsBefore = engine.queue.list().length;
    const port = engine.cfg.port;
    await engine.stop();
    engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port });
    await new Promise((r) => setTimeout(r, 500));
    await engine.queue.idle();
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    expect(videos.filter((v) => v.status === 'ready')).toHaveLength(2);
    // 깨진 파일은 다시 probe 하지 않는다 (failed 유지)
    expect(engine.queue.list().length).toBe(jobsBefore);
  });
});
