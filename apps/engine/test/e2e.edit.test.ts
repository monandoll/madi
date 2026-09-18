/**
 * 2단계 e2e: AI 미연결 버튼 4개가 진짜 ffmpeg 로 결과물을 만든다.
 * 자막(whisper)은 바이너리·모델이 있을 때만 (없으면 skip 하고 이유를 남긴다).
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ActionResponse, OutputDetailResponse, OutputsResponse, VideoDetailResponse, VideosResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { resolveSidecar, resolveWhisperModel } from '../src/main/sidecar.js';
import { FIXTURES, SAMPLE_5S, freePort, tempHome, waitFor } from './helpers.js';
import { makeDemoSilenceFixture } from './longform-fixture.js';

let home: string;
let watchDir: string;
let engine: Engine;
let videoId: string;

const api = async <T>(p: string, init?: RequestInit): Promise<T> => {
  const res = await fetch(`${engine.url}${p}`, init);
  if (!res.ok) throw new Error(`${p} → ${res.status} ${await res.text()}`);
  return (await res.json()) as T;
};
const act = (body: unknown) =>
  api<ActionResponse>(`/api/videos/${videoId}/actions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const detail = () => api<VideoDetailResponse>(`/api/videos/${videoId}`).then((d) => VideoDetailResponse.parse(d));
const waitJob = async (jobId: string) => {
  await waitFor(() => {
    const j = engine.queue.get(jobId);
    return !!j && (j.status === 'done' || j.status === 'failed');
  }, 120_000);
  await engine.queue.idle(); // 이어지는 렌더까지
};

function whisperAvailable(): boolean {
  const bin = resolveSidecar('whisper', '/nonexistent');
  const model = resolveWhisperModel(path.join(home, 'models'));
  if (!fs.existsSync(model.path)) return false;
  try {
    execFileSync(bin, ['--help'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

beforeAll(async () => {
  home = tempHome('madi-edit-');
  watchDir = path.join(home, 'videos');
  fs.mkdirSync(watchDir);
  process.env['MADI_QUIET'] = '1';
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
  fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(watchDir, '어깨 가동성 루틴.mp4'));
  await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ watchFolders: [watchDir], setupDone: true }) });
  await waitFor(async () => {
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    return videos.length === 1 && videos[0]!.status === 'ready';
  }, 60_000);
  videoId = VideosResponse.parse(await api('/api/videos')).videos[0]!.id;
});

afterAll(async () => {
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('edit actions (AI off)', () => {
  it('상세를 처음 열면 인사 한 마디, 자막·결과물은 없음', async () => {
    const d = await detail();
    expect(d.messages).toHaveLength(1);
    expect(d.messages[0]).toMatchObject({ role: 'assistant', kind: 'text', code: 'greeting' });
    expect(d.transcript).toBeNull();
    expect(d.outputs).toEqual([]);
    expect((await detail()).messages).toHaveLength(1); // 두 번 열어도 한 번만
  });

  it('세로로 바꾸기 → 1080x1920 결과물 + 결과물 카드 메시지', async () => {
    const res = await act({ type: 'vertical' });
    expect(res.job?.type).toBe('render');
    expect(res.messages.map((m) => [m.role, m.kind])).toEqual([
      ['user', 'text'],
      ['assistant', 'progress'],
    ]);
    await waitJob(res.job!.id);
    const d = await detail();
    expect(d.outputs).toHaveLength(1);
    const out = d.outputs[0]!;
    expect(out).toMatchObject({ width: 1080, height: 1920, kind: 'short' });
    expect(out.durationSec).toBeGreaterThan(7.5);
    expect(out.title).toContain('세로');
    const card = d.messages.find((m) => m.kind === 'output');
    expect(card?.outputId).toBe(out.id);
    expect(card?.code).toBe('output.ready');
    expect(d.messages.some((m) => m.kind === 'progress')).toBe(false);
  });

  it('쉬는 구간 잘라내기 → 무음 2구간이 빠져 4초 근처', async () => {
    const res = await act({ type: 'silence' });
    expect(res.job?.type).toBe('silence');
    await waitJob(res.job!.id);
    const d = await detail();
    const out = d.outputs.find((o) => o.title.includes('쉬는 구간'))!;
    expect(out).toBeTruthy();
    expect(out.durationSec).toBeGreaterThan(3.5);
    expect(out.durationSec).toBeLessThan(5);
    expect(out.kind).toBe('short'); // 5초 미만
    const od = OutputDetailResponse.parse(await api(`/api/outputs/${out.id}`));
    expect(od.edit.cuts).toHaveLength(2);
    expect(od.edit.cuts.every((c) => c.reason === 'silence')).toBe(true);
    const msg = d.messages.find((m) => m.outputId === out.id)!;
    expect(msg.params['cuts']).toBe(2);
  });

  it('동작 시범 중의 침묵은 남긴다 (말 없이 움직이는 구간은 자르지 않는다)', { timeout: 120_000 }, async () => {
    makeDemoSilenceFixture(path.join(watchDir, '햄스트링 시범.mp4'));
    await waitFor(async () => VideosResponse.parse(await api('/api/videos')).videos.some((v) => v.title === '햄스트링 시범' && v.status === 'ready'), 60_000);
    const demoId = VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === '햄스트링 시범')!.id;
    const res = ActionResponse.parse(await api(`/api/videos/${demoId}/actions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ type: 'silence' }) }));
    await waitJob(res.job!.id);
    await engine.queue.idle();
    const d = VideoDetailResponse.parse(await api(`/api/videos/${demoId}`));
    // 유일한 무음이 시범이라 잘라낼 곳이 없다 → 결과물 없이 한 마디, 남긴 곳 1
    expect(d.outputs).toEqual([]);
    const m = d.messages.find((x) => x.code === 'silence.none')!;
    expect(m).toBeTruthy();
    expect(m.params['kept']).toBe(1);
  });

  it('수동 숏폼: 구간을 세로 숏폼으로', async () => {
    const res = await act({ type: 'short', range: { start: 1, end: 3.5 }, subtitles: false });
    await waitJob(res.job!.id);
    const d = await detail();
    const out = d.outputs.find((o) => o.title.includes('숏폼'))!;
    expect(out).toMatchObject({ width: 1080, height: 1920, kind: 'short' });
    expect(Math.abs(out.durationSec - 2.5)).toBeLessThan(0.3);
    const od = OutputDetailResponse.parse(await api(`/api/outputs/${out.id}`));
    expect(od.edit.keep).toEqual({ start: 1, end: 3.5 });
    expect(od.edit.crop).toBe('vertical');
  });

  it('너무 짧은 구간·준비 안 된 영상은 409 로 거절', async () => {
    const res = await fetch(`${engine.url}/api/videos/${videoId}/actions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'short', range: { start: 2, end: 2.5 } }),
    });
    expect(res.status).toBe(409);
    expect((await res.json()).error.code).toBe('range_too_short');
  });

  it('결과물 목록·파일·다운로드 헤더', async () => {
    const { outputs } = OutputsResponse.parse(await api('/api/outputs'));
    expect(outputs.length).toBe(3);
    const o = outputs[0]!;
    const head = await fetch(`${engine.url}${o.url}`, { method: 'HEAD' });
    expect(head.status).toBe(200);
    expect(head.headers.get('accept-ranges')).toBe('bytes');
    const dl = await fetch(`${engine.url}${o.downloadUrl}`, { method: 'HEAD' });
    expect(dl.headers.get('content-disposition')).toContain('attachment');
    expect(dl.headers.get('content-disposition')).toContain(encodeURIComponent(o.title));
    expect(o.thumbnailUrl).toMatch(/\.jpg$/);
    const thumb = await fetch(`${engine.url}${o.thumbnailUrl}`);
    expect(thumb.status).toBe(200);
    // 갤러리 카드에 결과물 개수
    const { videos } = VideosResponse.parse(await api('/api/videos'));
    expect(videos.find((v) => v.id === videoId)!.outputCount).toBe(3);
  });

  it('자막 만들기 (whisper 있을 때만): 자막 + 번인 결과물', async (ctx) => {
    if (!whisperAvailable()) {
      ctx.skip();
      return;
    }
    fs.copyFileSync(path.join(FIXTURES, 'sample-5s.mp4'), path.join(watchDir, '햄스트링.mp4'));
    await waitFor(async () => VideosResponse.parse(await api('/api/videos')).videos.every((v) => v.status === 'ready'), 60_000);
    const res = await act({ type: 'subtitle' });
    expect(res.job?.type).toBe('transcribe');
    await waitJob(res.job!.id);
    const d = await detail();
    expect(d.transcript).not.toBeNull();
    const out = d.outputs.find((o) => o.title.includes('자막'));
    expect(out).toBeTruthy();
  });

  it('무음 영상에 자막·쉬는 구간은 부드럽게 거절 (no_audio)', async () => {
    fs.copyFileSync(path.join(FIXTURES, 'sample-silent-3s.mp4'), path.join(watchDir, '무음.mp4'));
    // 앞 테스트(자막)가 영상을 더 넣었을 수 있으니 '무음' 자체가 ready 될 때까지
    await waitFor(async () => {
      const { videos } = VideosResponse.parse(await api('/api/videos'));
      return videos.find((v) => v.title === '무음')?.status === 'ready';
    }, 60_000);
    const silent = VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === '무음')!;
    const res = await fetch(`${engine.url}/api/videos/${silent.id}/actions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'subtitle' }),
    });
    expect(res.status).toBe(409);
    expect((await res.json()).error.code).toBe('no_audio');
  });

  it('무음 영상에도 직접 쓴 자막은 넣는다 (PUT transcript → 자막 넣기 → 결과물)', async () => {
    const silent = VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === '무음')!;
    const put = await fetch(`${engine.url}/api/videos/${silent.id}/transcript`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ segments: [{ start: 0, end: 1.5, text: '무릎 펴기' }, { start: 1.5, end: 3, text: '천천히' }] }),
    });
    expect(put.status).toBe(200);
    const t = (await put.json()).transcript;
    expect(t.model).toBe('manual');
    expect(t.segments.map((s: { text: string }) => s.text)).toEqual(['무릎 펴기', '천천히']);
    const res = await api<ActionResponse>(`/api/videos/${silent.id}/actions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ type: 'subtitle' }) });
    expect(res.job?.type).toBe('render');
    await waitJob(res.job!.id);
    const d = VideoDetailResponse.parse(await api(`/api/videos/${silent.id}`));
    const out = d.outputs.find((o) => o.title.includes('자막'));
    expect(out).toBeTruthy();
    expect(fs.existsSync(out!.path)).toBe(true);
    // 같은 줄은 그대로, 바뀐 줄만 새로 (id 유지 확인)
    const again = await fetch(`${engine.url}/api/videos/${silent.id}/transcript`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ segments: [{ start: 0, end: 1.5, text: '무릎 펴기' }, { start: 1.5, end: 3, text: '아주 천천히' }] }),
    });
    const t2 = (await again.json()).transcript;
    expect(t2.segments[0].id).toBe(t.segments[0].id);
    expect(t2.segments[1].id).not.toBe(t.segments[1].id);
    expect((await fetch(`${engine.url}/api/videos/${silent.id}/transcript`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ segments: [] }) })).status).toBe(400);
  });
});
