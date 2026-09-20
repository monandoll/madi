/**
 * 2단계 e2e: AI 미연결 버튼 4개가 진짜 ffmpeg 로 결과물을 만든다.
 * 자막(whisper)은 바이너리·모델이 있을 때만 (없으면 skip 하고 이유를 남긴다).
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ActionResponse, OutputDetailResponse, OutputsResponse, VideoDetailResponse, VideosResponse, StyleResponse } from '@madi/shared';
import { type Engine, startEngine } from '../src/engine.js';
import { resolveSidecar, resolveWhisperModel } from '../src/main/sidecar.js';
import { FIXTURES, SAMPLE_5S, freePort, tempHome, waitFor } from './helpers.js';
import { makeDemoSilenceFixture, makeMotionPatchFixture } from './longform-fixture.js';

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

  it('AI 가 없으면 편집안은 409 ai_off, 편집안 없이 만들기는 409 plan_missing', async () => {
    const post = (body: unknown) => fetch(`${engine.url}/api/videos/${videoId}/actions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const a = await post({ type: 'plan' });
    expect(a.status).toBe(409);
    expect(((await a.json()) as { error: { code: string } }).error.code).toBe('ai_off');
    const b = await post({ type: 'apply_plan' });
    expect(b.status).toBe(409);
    expect(((await b.json()) as { error: { code: string } }).error.code).toBe('plan_missing');
    expect((await detail()).plan).toBeNull();
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
    // 빈 목록은 자막을 모두 지우는 명시적 수정이다.
    expect((await fetch(`${engine.url}/api/videos/${silent.id}/transcript`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ segments: [] }) })).status).toBe(200);
  });

  it('자막에서 고친 말은 남는다: 틀린 말 → 바른 말, 두 번이면 바로 바꿈, 빼면 사라진다 (기획안 §5.2)', async () => {
    const silent = VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === '무음')!;
    const put = (lines: { start: number; end: number; text: string }[]) =>
      fetch(`${engine.url}/api/videos/${silent.id}/transcript`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ segments: lines }) });
    // 문장을 아예 다시 쓴 건 교정이 아니다 ('무릎 펴기' → '겹갑골을 뒤로')
    await put([{ start: 0, end: 1.5, text: '겹갑골을 뒤로' }, { start: 1.5, end: 3, text: '아주 천천히' }]);
    expect(StyleResponse.parse(await api('/api/style')).corrections).toEqual([]);
    await put([{ start: 0, end: 1.5, text: '견갑골을 뒤로' }, { start: 1.5, end: 3, text: '아주 천천히' }]);
    let style = StyleResponse.parse(await api('/api/style'));
    expect(style.corrections).toEqual([expect.objectContaining({ wrong: '겹갑골', right: '견갑골', count: 1, videoId: silent.id })]);
    expect(engine.corrections.active()).toEqual([]); // 한 번은 아직 안 바꾼다
    expect(engine.corrections.rights()).toEqual(['견갑골']); // 그래도 whisper 에는 알려 준다
    await put([{ start: 0, end: 1.5, text: '견갑골을 뒤로' }, { start: 1.5, end: 3, text: '겹갑골이 아프면' }]);
    await put([{ start: 0, end: 1.5, text: '견갑골을 뒤로' }, { start: 1.5, end: 3, text: '견갑골이 아프면' }]);
    style = StyleResponse.parse(await api('/api/style'));
    expect(style.corrections[0]).toMatchObject({ wrong: '겹갑골', right: '견갑골', count: 2 });
    expect(engine.corrections.active()).toEqual([{ wrong: '겹갑골', right: '견갑골' }]);
    const del = await fetch(`${engine.url}/api/style/corrections/${style.corrections[0]!.id}`, { method: 'DELETE' });
    expect(del.status).toBe(200);
    expect(StyleResponse.parse(await del.json()).corrections).toEqual([]);
    expect((await fetch(`${engine.url}/api/style/corrections/nope`, { method: 'DELETE' })).status).toBe(404);
    // 자막을 원래대로 돌려놓는다 (뒤 테스트가 이 영상을 안 쓰지만 깔끔하게)
    await put([{ start: 0, end: 1.5, text: '무릎 펴기' }, { start: 1.5, end: 3, text: '아주 천천히' }]);
  });

  const ready = async (title: string) => {
    await waitFor(async () => VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === title)?.status === 'ready', 60_000);
    return VideosResponse.parse(await api('/api/videos')).videos.find((v) => v.title === title)!;
  };
  const actOn = (id: string, body: unknown) =>
    api<ActionResponse>(`/api/videos/${id}/actions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });

  it('세로로 바꾸기: 화면 오른쪽에서만 움직이면 오른쪽을 잡고, 그 결정이 Edit 에 남는다 (§5.4)', { timeout: 120_000 }, async () => {
    makeMotionPatchFixture(path.join(watchDir, '오른쪽 시범.mp4'), { x: 0.66, y: 0, w: 0.34, h: 1 });
    const v = await ready('오른쪽 시범');
    const res = await actOn(v.id, { type: 'vertical' });
    await waitJob(res.job!.id);
    const d = VideoDetailResponse.parse(await api(`/api/videos/${v.id}`));
    const out = d.outputs[0]!;
    expect(out).toMatchObject({ width: 1080, height: 1920 });
    const od = OutputDetailResponse.parse(await api(`/api/outputs/${out.id}`));
    expect(od.edit.cropFocus).toBe(1);
    const card = d.messages.find((m) => m.kind === 'output')!;
    expect(card.params['focus']).toBe('right');
    // 같은 Edit 로 다시 만들어도 같은 결정 (렌더는 Edit 로부터 재현)
    const again = engine.queue.enqueue({ type: 'render', videoId: v.id, editId: od.edit.id });
    await waitJob(again.id);
    expect(OutputDetailResponse.parse(await api(`/api/outputs/${out.id}`)).edit.cropFocus).toBe(1);
  });

  it('자막 넣기: 아래쪽에서 동작이 움직이면 자막을 위에 두고, 그 뒤로는 자동으로 바꾸지 않는다 (§5.5)', { timeout: 120_000 }, async () => {
    makeMotionPatchFixture(path.join(watchDir, '아래 동작.mp4'), { x: 0, y: 0.64, w: 1, h: 0.36 });
    const v = await ready('아래 동작');
    await fetch(`${engine.url}/api/videos/${v.id}/transcript`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ segments: [{ start: 0, end: 2, text: '무릎을 펴고' }, { start: 2, end: 4, text: '천천히' }] }),
    });
    const res = await actOn(v.id, { type: 'subtitle' });
    await waitJob(res.job!.id);
    const d = VideoDetailResponse.parse(await api(`/api/videos/${v.id}`));
    const od = OutputDetailResponse.parse(await api(`/api/outputs/${d.outputs[0]!.id}`));
    expect(od.edit.subtitleAuto).toBe(false);
    expect(od.edit.subtitleStyle.bottom).toBe(0.7);
    expect(d.messages.find((m) => m.kind === 'output')!.params['subtitleTop']).toBe(true);

    // 가만히 있는 화면(회색)이면 자막은 아래 그대로 — 그래도 "정했다"는 표시는 남는다
    makeMotionPatchFixture(path.join(watchDir, '가만히.mp4'), { x: 0, y: 0, w: 0.02, h: 0.02 });
    const still = await ready('가만히');
    await fetch(`${engine.url}/api/videos/${still.id}/transcript`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ segments: [{ start: 0, end: 3, text: '설명' }] }) });
    const r2 = await actOn(still.id, { type: 'subtitle' });
    await waitJob(r2.job!.id);
    const d2 = VideoDetailResponse.parse(await api(`/api/videos/${still.id}`));
    const od2 = OutputDetailResponse.parse(await api(`/api/outputs/${d2.outputs[0]!.id}`));
    expect(od2.edit.subtitleAuto).toBe(false);
    expect(od2.edit.subtitleStyle.bottom).toBe(0.18);
    expect(d2.messages.find((m) => m.kind === 'output')!.params['subtitleTop']).toBeUndefined();
  });
});
