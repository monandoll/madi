/**
 * 4단계 e2e: 채팅 → 에이전트(가짜 claude CLI) → 진짜 MCP 서버 프로세스 → 엔진 도구 API → 진짜 렌더.
 * 가짜 CLI 는 fixtures/fake-claude.mjs. 도구 호출은 실제 stdio JSON-RPC 로 오간다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ActionResponse, AiProvidersResponse, ChatResponse, HealthResponse, isStreaming, OutputDetailResponse, PlanResponse, VideoDetailResponse, VideosResponse } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, fakeCli, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let engine: Engine;
let videoId: string;
const FAKE = fakeCli('claude');
const FAKE_CODEX = fakeCli('codex');

const api = async <T>(p: string, init?: RequestInit): Promise<{ status: number; body: T }> => {
  const res = await fetch(`${engine.url}${p}`, init);
  return { status: res.status, body: (await res.json()) as T };
};
const json = (body: unknown): RequestInit => ({ method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const detail = () => api<VideoDetailResponse>(`/api/videos/${videoId}`).then((r) => VideoDetailResponse.parse(r.body));
const chat = (text: string) => api<ChatResponse>(`/api/videos/${videoId}/chat`, json({ text }));
const errCode = (body: unknown) => (body as { error: { code: string } }).error.code;
// 마지막 답 말풍선 (도구가 붙인 진행·결과 카드는 제외)
const lastReply = async () => (await detail()).messages.filter((m) => m.role === 'assistant' && m.kind !== 'output' && m.kind !== 'progress').at(-1)!;
const waitReply = async () => {
  await waitFor(async () => {
    const m = await lastReply();
    return !isStreaming(m) && !(await detail()).aiBusy;
  }, 60_000);
  return lastReply();
};

beforeAll(async () => {
  home = tempHome('madi-agent-');
  const watchDir = path.join(home, 'videos');
  fs.mkdirSync(watchDir);
  fs.chmodSync(FAKE, 0o755);
  process.env['MADI_QUIET'] = '1';
  process.env['MADI_CLAUDE_BIN'] = FAKE;
  process.env['MADI_CODEX_BIN'] = FAKE_CODEX;
  resetCliCache();
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
  fs.copyFileSync(path.join(FIXTURES, 'sample-gaps-8s.mp4'), path.join(watchDir, '햄스트링 스트레칭.mp4'));
  await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ watchFolders: [watchDir], setupDone: true }) });
  await waitFor(async () => {
    const { videos } = VideosResponse.parse((await api('/api/videos')).body);
    return videos.length === 1 && videos[0]!.status === 'ready';
  }, 60_000);
  videoId = VideosResponse.parse((await api('/api/videos')).body).videos[0]!.id;
});

afterAll(async () => {
  delete process.env['MADI_CLAUDE_BIN'];
  delete process.env['MADI_CODEX_BIN'];
  delete process.env['MADI_FAKE_CODEX'];
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('AI 연결', () => {
  it('미연결이면 채팅은 409, 러너를 띄우지 않는다', async () => {
    const h = HealthResponse.parse((await api('/api/health')).body);
    expect(h.ai).toEqual({ connected: false, provider: 'none', installed: false });
    const r = await chat('세로로 바꿔줘');
    expect(r.status).toBe(409);
    expect(errCode(r.body)).toBe('ai_off');
    expect((await detail()).messages.filter((m) => m.code === 'user.text')).toHaveLength(0);
  });

  it('설치된 도구 목록: 가짜 claude 가 보인다', async () => {
    const p = AiProvidersResponse.parse((await api('/api/ai/providers?fresh=1')).body);
    expect(p.providers.find((x) => x.id === 'claude')).toMatchObject({ installed: true, version: '9.9.9', label: 'Claude Code' });
  });

  it('프로바이더를 고르면 health.ai 가 연결됨', async () => {
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ai: { provider: 'claude' } }) });
    await waitFor(async () => HealthResponse.parse((await api('/api/health')).body).ai.connected, 15_000);
    const h = HealthResponse.parse((await api('/api/health')).body);
    expect(h.ai).toEqual({ connected: true, provider: 'claude', installed: true });
  });

  it('채팅 → 답이 스트리밍으로 채워지고, 도구로 만든 세로 결과물 카드가 붙는다', async () => {
    const r = await chat('세로로 바꿔줘');
    expect(r.status).toBe(200);
    const { messages } = ChatResponse.parse(r.body);
    expect(messages.map((m) => [m.role, m.code])).toEqual([
      ['user', 'user.text'],
      ['assistant', 'ai.text'],
    ]);
    expect(messages[1]!.params).toEqual({ text: '', streaming: true });
    expect((await detail()).aiBusy).toBe(true);
    // 돌아가는 동안 또 보내면 409
    const busy = await chat('하나 더');
    expect(busy.status).toBe(409);
    expect(errCode(busy.body)).toBe('ai_busy');

    const reply = await waitReply();
    expect(reply.code).toBe('ai.text');
    expect(String(reply.params['text'])).toContain('세로로 만들게요.');
    expect(String(reply.params['text'])).toContain('「AI 세로」 만들었어요');
    const d = await detail();
    expect(d.aiBusy).toBe(false);
    expect(d.outputs).toHaveLength(1);
    expect(d.outputs[0]).toMatchObject({ title: 'AI 세로', width: 1080, height: 1920 });
    // 진행 카드가 결과 카드로 바뀌어 있다 (도구가 만든 것)
    const card = d.messages.find((m) => m.kind === 'output');
    expect(card).toMatchObject({ outputId: d.outputs[0]!.id, params: expect.objectContaining({ action: 'ai', title: 'AI 세로' }) });
    // 시스템 프롬프트에 style.md 와 제작 지침이 같이 들어갔다
    const r2 = await chat('안녕');
    expect(r2.status).toBe(200);
    const sys = String((await waitReply()).params['text']);
    expect(sys).toContain('규칙 읽었어요');
    expect(sys).toContain('지침 있어요');
    expect(sys).toContain('기억 없어요');
    // 기억을 한 줄 넣으면 다음 요청부터 같이 간다
    expect((await api('/api/style/memory', json({ text: '도입은 질문으로 연다' }))).status).toBe(200);
    const r3 = await chat('안녕');
    expect(r3.status).toBe(200);
    expect(String((await waitReply()).params['text'])).toContain('기억 있어요');
  });

  it('extract_shorts 의 parts: 뒤 조각을 앞에 — 순서대로 이어 붙인 숏폼, focus 는 Edit 에 남는다', { timeout: 120_000 }, async () => {
    const before = (await detail()).outputs.length;
    expect((await chat('조각으로 숏폼 만들어줘')).status).toBe(200);
    const reply = await waitReply();
    expect(String(reply.params['text'])).toContain('「AI 조각」 만들었어요');
    const d = await detail();
    expect(d.outputs).toHaveLength(before + 1);
    const out = d.outputs.find((o) => o.title === 'AI 조각')!;
    expect(out).toMatchObject({ width: 1080, height: 1920 });
    expect(Math.abs(out.durationSec - 4)).toBeLessThan(0.4);
    const od = OutputDetailResponse.parse(await api(`/api/outputs/${out.id}`).then((r) => r.body));
    expect(od.edit.parts).toEqual([
      { start: 3, end: 5 },
      { start: 0, end: 2 },
    ]);
    expect(od.edit.cropFocus).toBe(0);
    // 결과물 자막 목록도 조각 순서를 따른다 (자막이 없으니 비어 있지만, 시각 재배치는 keepSegments 가 같이 쓴다)
    expect(od.edit.keep).toEqual({ start: 0, end: 5 });
  });

  it('set_subtitle_text: 사용자 문장이 자막이 된다 (자막이 없어도)', async () => {
    await chat('이 문장 고쳐줘: 안녕하세요 앱 소개합니다');
    const m = await waitReply();
    expect(String(m.params['text'])).toContain('"안녕하세요 앱 소개합니다" 로 바꿨어요');
    const t = engine.library.transcriptOf(videoId)!;
    expect(t.model).toBe('manual');
    expect(t.segments.map((s) => s.text)).toEqual(['안녕하세요 앱 소개합니다']);
    expect(t.segments[0]).toMatchObject({ start: 0, end: 2 });
  });

  it('결과물이 있는 편집을 고치면 새 편집(revisionOf)이 되고, 결과물 화면은 이전 것과 달라진 점을 같이 준다 (기획안 §6)', { timeout: 120_000 }, async () => {
    const first = (await detail()).outputs.find((o) => o.title === 'AI 세로')!;
    const before = OutputDetailResponse.parse((await api(`/api/outputs/${first.id}`)).body);
    expect(before.previous).toBeNull();
    await chat(`고쳐줘: ${before.edit.id}`);
    const reply = await waitReply();
    expect(String(reply.params['text'])).toContain('1곳을 더 잘라냈어요. 이전 것과 비교할 수 있어요.');
    const out = (await detail()).outputs.find((o) => o.editId !== before.edit.id && o.title === 'AI 세로')!;
    expect(out).toBeTruthy();
    const od = OutputDetailResponse.parse((await api(`/api/outputs/${out.id}`)).body);
    expect(od.edit.revisionOf).toBe(before.edit.id);
    expect(od.edit.cuts).toEqual([{ start: 0, end: 1, reason: 'ai' }]);
    expect(od.previous?.output.id).toBe(first.id);
    expect(od.previous?.edit.cuts).toEqual([]); // 이전 편집은 그대로 — 이전 결과물은 여전히 재현된다
    expect(Math.abs(od.output.durationSec - (first.durationSec - 1))).toBeLessThan(0.4);
  });

  it('apply_edit.emphasis: 단어를 그 구간에서만 강조한 자막 결과물 (기획안 §6 예시 2)', { timeout: 120_000 }, async () => {
    await chat('강조해줘: 앱');
    const m = await waitReply();
    expect(String(m.params['text'])).toContain('「AI 강조」 만들었어요. 1개 단어를 띄웠어요.');
    const out = (await detail()).outputs.find((o) => o.title === 'AI 강조')!;
    expect(out).toBeTruthy();
    const od = OutputDetailResponse.parse((await api(`/api/outputs/${out.id}`)).body);
    expect(od.edit.subtitles).toBe(true);
    expect(od.edit.emphasis).toEqual([{ term: '앱', start: 0, end: 2 }]);
    expect(od.edit.subtitleStyle.emphasisColor).toBe('#3E6B8A');
  });

  it('update_style_rule 은 style.md 에 한 줄 붙인다', async () => {
    await chat('규칙 저장해줘');
    expect(String((await waitReply()).params['text'])).toContain('앞으로 그렇게 할게요.');
    expect(fs.readFileSync(engine.style.mdPath, 'utf8')).toContain('- 숏폼은 30초 안쪽으로');
  });

  // 편집안은 자막이 없으면 먼저 만든다 (CI 엔 whisper 가 있다) — 자막이 없다는 전제의 set_subtitle_text 뒤에서 돈다
  it('편집안: AI 한 턴으로 구성 · 남길 곳 · 잘라낼 후보 · 숏폼 후보가 나오고, 다음 요청의 프롬프트에 같이 간다', { timeout: 120_000 }, async () => {
    const r = await api<ActionResponse>(`/api/videos/${videoId}/actions`, json({ type: 'plan' }));
    expect(r.status).toBe(200);
    const res = ActionResponse.parse(r.body);
    expect(res.job?.type).toBe('plan');
    expect(res.messages.map((m) => m.code)).toEqual(['action.plan', 'progress.plan']);
    // 이미 걸려 있으면 또 걸지 않는다
    const again = ActionResponse.parse((await api(`/api/videos/${videoId}/actions`, json({ type: 'plan' }))).body);
    expect(again.job?.id).toBe(res.job?.id);
    await waitFor(async () => (await detail()).plan !== null, 90_000);
    await engine.queue.idle();
    const d = await detail();
    const plan = d.plan!;
    expect(plan).toMatchObject({ videoId, provider: 'claude' });
    expect(plan.purpose).toContain('햄스트링 스트레칭');
    expect(plan.sections.length).toBeGreaterThanOrEqual(2);
    expect(plan.sections[0]!.note).toBe('인사는 빼고 핵심 문장부터');
    expect(plan.keepRanges[0]!.why).toContain('시범');
    expect(plan.cutCandidates[0]).toMatchObject({ kind: 'aside', why: '인사 · 촬영 세팅 멘트' });
    expect(plan.shortCandidates[0]).toMatchObject({ channel: 'reels' });
    for (const x of [...plan.sections, ...plan.keepRanges, ...plan.cutCandidates, ...plan.shortCandidates]) expect(x.end).toBeLessThanOrEqual(plan.sections[plan.sections.length - 1]!.end);
    // 화면 시트를 만들어 보여 줬다 (기획안 §10): 가짜 CLI 는 Read 가 sheets/ 에 열려 있고 파일이 있을 때만 "봤다"고 답한다
    expect(plan.frameTimes.length).toBeGreaterThan(0);
    expect(plan.framing).toEqual({ side: 'right', note: '사람이 오른쪽에 서 있다' });
    const card = d.messages.find((m) => m.kind === 'plan')!;
    expect(card).toMatchObject({ code: 'plan.ready', params: expect.objectContaining({ sections: plan.sections.length, shorts: 1, cuts: 1 }) });
    expect(d.messages.some((m) => m.kind === 'progress')).toBe(false);
    // 다음 채팅 요청에 편집안이 같이 간다
    await chat('안녕');
    expect(String((await waitReply()).params['text'])).toContain('편집안 있어요');
  });

  it('편집안의 숏폼 후보를 누르면 화면에서 본 사람 위치(오른쪽)를 잡는다 (§5.4 · §10)', { timeout: 120_000 }, async () => {
    const plan = (await detail()).plan!;
    const cand = plan.shortCandidates[0]!;
    const r = ActionResponse.parse((await api(`/api/videos/${videoId}/actions`, json({ type: 'short', range: { start: cand.start, end: cand.end }, subtitles: false, from: 'plan' }))).body);
    await waitFor(() => engine.queue.get(r.job!.id)?.status === 'done', 90_000);
    await engine.queue.idle();
    const out = (await detail()).outputs.find((o) => o.title.includes('숏폼'))!;
    const od = OutputDetailResponse.parse((await api(`/api/outputs/${out.id}`)).body);
    expect(od.edit.cropFocus).toBe(1);
    expect((await detail()).plan!.feedback).toEqual([expect.objectContaining({ kind: 'short', index: 0, verdict: 'accepted' })]);
  });

  it('"화면도 보여 주기"를 끄면 시트 없이 읽는다 (framing 없음)', { timeout: 120_000 }, async () => {
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ai: { provider: 'claude', paths: { claude: null, codex: null }, frames: false } }) });
    const r = ActionResponse.parse((await api(`/api/videos/${videoId}/actions`, json({ type: 'plan' }))).body);
    await waitFor(() => engine.queue.get(r.job!.id)?.status === 'done', 90_000);
    const plan = (await detail()).plan!;
    expect(plan.framing).toBeNull();
    expect(plan.frameTimes).toEqual([]);
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ai: { provider: 'claude', paths: { claude: null, codex: null }, frames: true } }) });
  });

  it('편집안대로 롱폼 만들기: 잘라낼 후보만 빠진 결과물', { timeout: 120_000 }, async () => {
    const r = ActionResponse.parse((await api(`/api/videos/${videoId}/actions`, json({ type: 'apply_plan' }))).body);
    expect(r.messages.map((m) => m.code)).toEqual(['action.apply_plan', 'progress.render']);
    expect(r.messages[0]!.params['cuts']).toBe(1);
    await waitFor(async () => (await detail()).outputs.some((o) => o.title.includes('편집안')), 90_000);
    await engine.queue.idle();
    const out = (await detail()).outputs.find((o) => o.title.includes('편집안'))!;
    const od = OutputDetailResponse.parse((await api(`/api/outputs/${out.id}`)).body);
    expect(od.edit.cuts).toEqual([{ start: 0, end: 1, reason: 'ai' }]);
    expect(od.edit.crop).toBe('none');
  });

  it('편집안 후보 빼기: 만들기에서 빠지고, 프롬프트에 "뺀 후보" 로 가고, 세 번 빼면 기억 제안 (기획안 §9)', { timeout: 120_000 }, async () => {
    const fb = (verdict: 'rejected' | null) => api<PlanResponse>(`/api/videos/${videoId}/plan/feedback`, json({ kind: 'cut', index: 0, verdict }));
    const r = await fb('rejected');
    expect(r.status).toBe(200);
    expect(PlanResponse.parse(r.body).plan.feedback).toEqual([expect.objectContaining({ kind: 'cut', index: 0, verdict: 'rejected' })]);
    // 없는 자리 · 편집안 없는 영상은 거절
    expect((await api(`/api/videos/${videoId}/plan/feedback`, json({ kind: 'short', index: 9, verdict: 'rejected' }))).status).toBe(404);
    // 편집안대로 만들기 → 빠진 컷 0
    const a = ActionResponse.parse((await api(`/api/videos/${videoId}/actions`, json({ type: 'apply_plan' }))).body);
    expect(a.messages[0]!.params['cuts']).toBe(0);
    await engine.queue.idle();
    const outs = (await detail()).outputs.filter((o) => o.title.includes('편집안'));
    const od = OutputDetailResponse.parse((await api(`/api/outputs/${outs[0]!.id}`)).body);
    expect(od.edit.cuts).toEqual([]);
    // 다음 요청의 프롬프트에 뺀 후보가 간다
    await chat('안녕');
    expect(String((await waitReply()).params['text'])).toContain('뺀 후보 있어요');
    // 되돌리기 → 다시 빼기 ×2 → 같은 종류(잡담) 세 번째에 기억 제안 (proposed)
    expect(engine.memory.list().some((m) => m.text.includes('잡담'))).toBe(false);
    await fb(null);
    await fb('rejected');
    await fb(null);
    await fb('rejected');
    const m = engine.memory.list().find((x) => x.text.includes('잡담'))!;
    expect(m).toMatchObject({ kind: 'keep', scope: 'all', source: 'feedback', status: 'proposed' });
    await fb(null);
    expect(String((await chat('안녕'), await waitReply()).params['text'])).toContain('뺀 후보 없어요');
  });

  it('에이전트 실패는 채팅 안에 오류 말풍선', async () => {
    await chat('실패해봐');
    const m = await waitReply();
    expect(m.kind).toBe('error');
    expect(m.code).toBe('ai_failed');
  });

  it('취소하면 바로 멈춘다', async () => {
    await chat('느리게 해줘');
    await waitFor(async () => String((await lastReply()).params['text']).includes('천천히'), 20_000);
    const c = await api<{ canceled: boolean }>(`/api/videos/${videoId}/chat/cancel`, { method: 'POST' });
    expect(c.body.canceled).toBe(true);
    const m = await waitReply();
    expect(isStreaming(m)).toBe(false);
    expect(String(m.params['text'])).toContain('천천히 할게요.');
    expect(String(m.params['text'])).not.toContain('다 했어요');
  });

  it('도구 API 는 토큰 없이는 403', async () => {
    const r = await api(`/api/agent/tools/apply_edit`, json({ videoId, input: {} }));
    expect(r.status).toBe(403);
  });

  it('CLI 가 사라지면 health 는 미설치, 채팅은 설치 안내 오류', async () => {
    process.env['MADI_CLAUDE_BIN'] = path.join(home, 'nope');
    resetCliCache();
    const h = HealthResponse.parse((await api('/api/health')).body);
    expect(h.ai).toEqual({ connected: false, provider: 'claude', installed: false });
    await chat('세로로 바꿔줘');
    const m = await waitReply();
    expect(m).toMatchObject({ kind: 'error', code: 'ai_missing' });
    process.env['MADI_CLAUDE_BIN'] = FAKE;
    resetCliCache();
  });

  it('Codex: 가짜 codex 로 답이 오고, 로그인 안 됐으면 ai_login 오류', async () => {
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ai: { provider: 'codex' } }) });
    resetCliCache();
    const h = HealthResponse.parse((await api('/api/health')).body);
    expect(h.ai).toEqual({ connected: true, provider: 'codex', installed: true });
    await chat('안녕');
    let m = await waitReply();
    expect(m.kind).toBe('text');
    expect(String(m.params['text'])).toContain('코덱스가 "안녕" 라고 들었어요');
    process.env['MADI_FAKE_CODEX'] = 'login';
    await chat('안녕');
    m = await waitReply();
    expect(m).toMatchObject({ kind: 'error', code: 'ai_login' });
    expect(String(m.params['detail'])).toContain('Not logged in');
    delete process.env['MADI_FAKE_CODEX'];
    await api('/api/settings', { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ai: { provider: 'claude' } }) });
    resetCliCache();
  });
});
