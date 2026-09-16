/**
 * 6단계 e2e: 긴 영상(ffmpeg 로 만든 4장면 × 50초) → 챕터 나누기(장면·무음) → 챕터 카드 → 숏폼 자동 추출 → 세로 결과물들.
 * 이 테스트는 whisper 를 일부러 끈다(MADI_WHISPER 를 없는 경로로): 톤 오디오에 whisper 가 지어내는 자막이 결과를 흔들지 않게.
 * 자막이 있을 때의 문장 경계 로직은 chapters.test.ts 가 본다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ActionResponse, VideoDetailResponse, VideosResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';
import { makeLongformFixture } from './longform-fixture.js';

let home: string;
let engine: Engine;
let videoId: string;
let prevWhisper: string | undefined;

const api = async <T>(p: string, init?: RequestInit): Promise<{ status: number; body: T }> => {
  const res = await fetch(`${engine.url}${p}`, init);
  return { status: res.status, body: (await res.json()) as T };
};
const json = (body: unknown): RequestInit => ({ method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const detail = () => api<VideoDetailResponse>(`/api/videos/${videoId}`).then((r) => VideoDetailResponse.parse(r.body));
const act = (body: unknown) => api<ActionResponse>(`/api/videos/${videoId}/actions`, json(body));

beforeAll(async () => {
  home = tempHome('madi-long-');
  const watchDir = path.join(home, 'videos');
  fs.mkdirSync(watchDir);
  makeLongformFixture(path.join(watchDir, '햄스트링 풀버전.mp4'), { scenes: 4, sceneSec: 50 });
  process.env['MADI_QUIET'] = '1';
  prevWhisper = process.env['MADI_WHISPER'];
  process.env['MADI_WHISPER'] = path.join(home, 'no-whisper-here');
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
  await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ watchFolders: [watchDir], setupDone: true }) });
  await waitFor(async () => {
    const { videos } = VideosResponse.parse((await api('/api/videos')).body);
    return videos.length === 1 && videos[0]!.status === 'ready';
  }, 120_000);
  videoId = VideosResponse.parse((await api('/api/videos')).body).videos[0]!.id;
}, 180_000);

afterAll(async () => {
  if (prevWhisper === undefined) delete process.env['MADI_WHISPER'];
  else process.env['MADI_WHISPER'] = prevWhisper;
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('롱폼', () => {
  it('긴 영상은 long, 챕터는 아직 없음', async () => {
    const d = await detail();
    expect(d.video.kind).toBe('long');
    expect(d.video.durationSec).toBeGreaterThan(190);
    expect(d.chapters).toBeNull();
  });

  it('챕터 나누기 → 장면 경계 4개 챕터, 카드 메시지', { timeout: 240_000 }, async () => {
    const r = await act({ type: 'chapters' });
    expect(r.status).toBe(200);
    expect(r.body.job?.type).toBe('chapters');
    expect(r.body.messages.map((m) => m.code)).toEqual(['action.chapters', 'progress.chapters']);
    await waitFor(async () => (await detail()).chapters !== null, 120_000);
    await engine.queue.idle();
    const d = await detail();
    const ch = d.chapters!;
    expect(ch.fromTranscript).toBe(false); // whisper 꺼짐 → 장면·무음만
    expect(ch.items).toHaveLength(4);
    expect(ch.items.map((c) => c.title)).toEqual(['1부', '2부', '3부', '4부']);
    for (const [i, c] of ch.items.entries()) {
      expect(c.start).toBeCloseTo(i * 50, 0);
      expect(c.end - c.start).toBeGreaterThan(45);
      // 50초 챕터는 60초 이하 → 통째로 하이라이트
      expect(c.highlight).toEqual({ start: c.start, end: c.end });
    }
    const card = d.messages.find((m) => m.kind === 'chapters')!;
    expect(card).toMatchObject({ code: 'chapters.ready', params: expect.objectContaining({ count: 4 }) });
  });

  it('숏폼 자동 추출: 챕터마다 하나씩, max 2 → 세로 결과물 2개', { timeout: 300_000 }, async () => {
    const r = await act({ type: 'auto_shorts', max: 2 });
    expect(r.status).toBe(200);
    await waitFor(async () => (await detail()).outputs.length === 2, 280_000);
    await engine.queue.idle();
    const d = await detail();
    expect(d.outputs.every((o) => o.width === 1080 && o.height === 1920)).toBe(true);
    expect(d.outputs.map((o) => Math.round(o.durationSec)).sort()).toEqual([50, 50]);
    expect(d.outputs.map((o) => o.title).sort()).toEqual(['햄스트링 풀버전 · 숏폼 1 · 1부', '햄스트링 풀버전 · 숏폼 2 · 2부']);
    const card = d.messages.find((m) => m.code === 'chapters.shorts')!;
    expect(card.params).toMatchObject({ count: 4, shorts: 2 });
    expect(d.messages.filter((m) => m.kind === 'output')).toHaveLength(2);
  });

  it('짧은 영상은 챕터를 못 나눈다 (409)', async () => {
    const short = path.join(home, 'videos', '짧은.mp4');
    fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), short);
    await waitFor(async () => VideosResponse.parse((await api('/api/videos')).body).videos.some((v) => v.title === '짧은' && v.status === 'ready'), 60_000);
    const v = VideosResponse.parse((await api('/api/videos')).body).videos.find((x) => x.title === '짧은')!;
    const r = await api<{ error: { code: string } }>(`/api/videos/${v.id}/actions`, json({ type: 'chapters' }));
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('too_short_for_chapters');
  });
});
