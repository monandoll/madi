/**
 * 4단계 e2e: 채팅 → 에이전트(가짜 claude CLI) → 진짜 MCP 서버 프로세스 → 엔진 도구 API → 진짜 렌더.
 * 가짜 CLI 는 fixtures/fake-claude.mjs. 도구 호출은 실제 stdio JSON-RPC 로 오간다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ActionResponse, AiProvidersResponse, ChatResponse, HealthResponse, isStreaming, OutputDetailResponse, VideoDetailResponse, VideosResponse } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let engine: Engine;
let videoId: string;
const FAKE = path.join(FIXTURES, 'fake-claude.mjs');
const FAKE_CODEX = path.join(FIXTURES, 'fake-codex.mjs');

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
    const card = d.messages.find((m) => m.kind === 'plan')!;
    expect(card).toMatchObject({ code: 'plan.ready', params: expect.objectContaining({ sections: plan.sections.length, shorts: 1, cuts: 1 }) });
    expect(d.messages.some((m) => m.kind === 'progress')).toBe(false);
    // 다음 채팅 요청에 편집안이 같이 간다
    await chat('안녕');
    expect(String((await waitReply()).params['text'])).toContain('편집안 있어요');
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

  it('set_subtitle_text: 사용자 문장이 자막이 된다 (자막이 없어도)', async () => {
    await chat('이 문장 고쳐줘: 안녕하세요 앱 소개합니다');
    const m = await waitReply();
    expect(String(m.params['text'])).toContain('"안녕하세요 앱 소개합니다" 로 바꿨어요');
    const t = engine.library.transcriptOf(videoId)!;
    expect(t.model).toBe('manual');
    expect(t.segments.map((s) => s.text)).toEqual(['안녕하세요 앱 소개합니다']);
    expect(t.segments[0]).toMatchObject({ start: 0, end: 2 });
  });

  it('update_style_rule 은 style.md 에 한 줄 붙인다', async () => {
    await chat('규칙 저장해줘');
    expect(String((await waitReply()).params['text'])).toContain('앞으로 그렇게 할게요.');
    expect(fs.readFileSync(engine.style.mdPath, 'utf8')).toContain('- 숏폼은 30초 안쪽으로');
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
