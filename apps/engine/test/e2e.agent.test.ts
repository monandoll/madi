/**
 * 4단계 e2e: 채팅 → 에이전트(가짜 claude CLI) → 진짜 MCP 서버 프로세스 → 엔진 도구 API → 진짜 렌더.
 * 가짜 CLI 는 fixtures/fake-claude.mjs. 도구 호출은 실제 stdio JSON-RPC 로 오간다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AiProvidersResponse, ChatResponse, HealthResponse, isStreaming, VideoDetailResponse, VideosResponse } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let engine: Engine;
let videoId: string;
const FAKE = path.join(FIXTURES, 'fake-claude.mjs');

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
    // 시스템 프롬프트에 style.md 가 들어갔다
    const r2 = await chat('안녕');
    expect(r2.status).toBe(200);
    expect(String((await waitReply()).params['text'])).toContain('규칙 읽었어요');
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
});
