/**
 * 엔진 e2e: 진짜 서버 + 진짜 ffmpeg.
 * 감시 폴더에 샘플을 넣으면 → 등록 → probe → 썸네일·프록시 → ready 가 API/WS/미디어로 보이는지.
 */
import fs from 'node:fs';
import path from 'node:path';
import WebSocket from 'ws';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { FoldersResponse, HealthResponse, SettingsResponse, VideosResponse, WsEvent, UpdateResponse } from '@madi/shared';
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
    const h = HealthResponse.parse(await api('/api/health'));
    expect(h.ok).toBe(true);
    expect(h.ai.connected).toBe(false);
    expect(h.tunnel.status).toBe('off');
  });

  it('새 버전: 브라우저만 뜬 상태면 최신이고 확인 · 설치는 409, 훅을 붙이면 받아 둔 뒤에만 설치된다', async () => {
    const h = HealthResponse.parse(await api('/api/health'));
    expect(h.update).toEqual({ available: null, downloaded: false, canInstall: false });
    const u = UpdateResponse.parse(await api('/api/update')).update;
    expect(u).toMatchObject({ current: h.version, available: null, canInstall: false });
    const post = (p: string) => fetch(`${engine.url}${p}`, { method: 'POST' });
    expect((await post('/api/update/check')).status).toBe(409);
    expect((await post('/api/update/install')).status).toBe(409);
    // Electron 이 붙이는 훅을 흉내 낸다
    let installed = 0;
    engine.update.setHooks({ check: async () => engine.update.available('9.9.9'), install: () => void installed++ });
    const checked = UpdateResponse.parse(await (await post('/api/update/check')).json()).update;
    expect(checked).toMatchObject({ available: '9.9.9', downloaded: false, canInstall: false });
    expect((await post('/api/update/install')).status).toBe(409); // 아직 안 받았다
    engine.update.downloaded('9.9.9');
    expect(HealthResponse.parse(await api('/api/health')).update).toEqual({ available: '9.9.9', downloaded: true, canInstall: true });
    expect((await post('/api/update/install')).status).toBe(200);
    expect(installed).toBe(1);
    engine.update.setHooks(null);
    engine.update.notAvailable();
  });

  it('설정을 바꾸면 감시가 시작되고, 폴더에 넣은 영상이 ready 가 된다', async () => {
    // 감시 전에 하나 미리 두고, 감시 시작 후 하나 더 복사 (초기 스캔 + 실시간 둘 다)
    fs.copyFileSync(SAMPLE_SILENT, path.join(watchDir, '거북목 교정.mp4'));
    await api('/api/settings', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ workspaceName: '우리 스튜디오', watchFolders: [watchDir] }),
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

  it('설정은 보낸 키만 바뀐다 (ai 만 보내도 setupDone 이 기본값으로 돌아가지 않는다)', async () => {
    const patch = (body: unknown) => api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    await patch({ setupDone: true });
    const after = SettingsResponse.parse(await patch({ ai: { provider: 'none' } }));
    expect(after.settings.setupDone).toBe(true);
    expect(after.settings.workspaceName).toBe('우리 스튜디오');
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

  it('폴더 후보: 흔한 폴더와 감시 중인 폴더를 영상 개수와 함께 준다', async () => {
    const root = path.join(home, 'suggest');
    fs.mkdirSync(path.join(root, 'Videos'), { recursive: true });
    fs.mkdirSync(path.join(root, 'Downloads', 'sub'), { recursive: true });
    fs.copyFileSync(SAMPLE_SILENT, path.join(root, 'Downloads', 'sub', 'a.MOV'));
    fs.writeFileSync(path.join(root, 'Downloads', 'note.txt'), '');
    process.env['MADI_SUGGEST_ROOT'] = root;
    try {
      const { folders } = FoldersResponse.parse(await api('/api/folders/suggest'));
      const byLabel = Object.fromEntries(folders.map((f) => [f.label, f]));
      expect(byLabel['동영상']).toMatchObject({ path: path.join(root, 'Videos'), videoCount: 0, selected: false });
      expect(byLabel['다운로드']).toMatchObject({ videoCount: 1, selected: false });
      expect(byLabel['바탕화면']).toBeUndefined(); // 없는 폴더는 안 나온다
      const watching = folders.find((f) => f.path === path.resolve(watchDir))!;
      expect(watching.selected).toBe(true);
      expect(watching.videoCount).toBeGreaterThanOrEqual(2);
    } finally {
      delete process.env['MADI_SUGGEST_ROOT'];
    }
    // 브라우저만 뜬 상태에선 시스템 선택창이 없다
    const pick = await fetch(`${engine.url}/api/folders/pick`, { method: 'POST' });
    expect(pick.status).toBe(501);
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
