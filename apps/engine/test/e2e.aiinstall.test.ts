/**
 * 안 깔린 PC e2e: 설정에서 "이 컴퓨터에 깔기" 한 번 → 마디가 설치기를 대신 돌리고 → 다 되면 바로 연결할 수 있다.
 * 진짜 설치기 대신 가짜 스크립트(MADI_INSTALL_CODEX)를 쓴다 — 실제 인터넷을 타지 않는다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AiInstallResponse, AiProvidersResponse } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome, waitFor } from './helpers.js';

let home: string;
let engine: Engine;
let landing: string;

const get = (p: string) => fetch(`${engine.url}${p}`);
const post = (p: string, body: unknown) => fetch(`${engine.url}${p}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const del = (p: string) => fetch(`${engine.url}${p}`, { method: 'DELETE' });
const installState = async () => AiInstallResponse.parse(await (await get('/api/ai/install')).json());
const codexOf = async () => AiProvidersResponse.parse(await (await get('/api/ai/providers')).json()).providers.find((p) => p.id === 'codex')!;
const errCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

beforeAll(async () => {
  home = tempHome('madi-aiinstall-');
  landing = path.join(home, 'bin', 'codex');
  // 진짜 설치기도 PATH 에 있는 자리(~/.local/bin)에 놓는다. 여기서는 임시 폴더로 흉내 낸다.
  fs.mkdirSync(path.dirname(landing), { recursive: true });
  process.env['PATH'] = `${path.dirname(landing)}${path.delimiter}${process.env['PATH'] ?? ''}`;
  process.env['MADI_QUIET'] = '1';
  delete process.env['MADI_CODEX_BIN'];
  // "설치기": 가짜 codex 를 이 PC 어딘가에 놓는다. 엔진은 그 뒤 진짜 도는지 실행해 본다.
  process.env['MADI_INSTALL_CODEX'] = `mkdir -p "${path.dirname(landing)}" && cp "${path.join(FIXTURES, 'fake-codex.mjs')}" "${landing}" && chmod +x "${landing}"`;
  resetCliCache();
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  delete process.env['MADI_INSTALL_CODEX'];
  delete process.env['MADI_CODEX_BIN'];
  fs.rmSync(home, { recursive: true, force: true });
});

describe('마디가 대신 깔기', () => {
  it('처음엔 아무것도 안 하고 있다', async () => {
    const s = await installState();
    expect(s.install).toMatchObject({ provider: null, status: 'idle' });
  });

  it('화면이 쓸 정보를 같이 준다 — 깔아 줄 수 있는지와 직접 칠 한 줄', async () => {
    const codex = await codexOf();
    expect(codex.canInstall).toBe(true);
    expect(codex.installLine).toContain('chatgpt.com/codex/install');
    // 사용자가 직접 칠 줄에도 node·npm 은 없다
    expect(codex.installLine).not.toMatch(/npm|node/);
  });

  it('깔기를 누르면 돌아가고, 끝나면 설치됨으로 바뀐다', async () => {
    expect((await post('/api/ai/install', { provider: 'codex' })).status).toBe(200);
    const started = await installState();
    expect(started.install).toMatchObject({ provider: 'codex', status: 'running' });

    await waitFor(async () => (await installState()).install.status === 'done', 60_000);
    const done = await installState();
    expect(done.install.error).toBeNull();
    // 같은 응답에 찾은 결과가 실려 있어 화면이 바로 "연결하기"로 넘어간다
    const codex = done.providers.find((p) => p.id === 'codex')!;
    expect(codex).toMatchObject({ installed: true });
    expect(fs.existsSync(landing)).toBe(true);
  });

  it('깔았으면 연결까지 이어진다', async () => {
    const res = await fetch(`${engine.url}/api/settings`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ai: { provider: 'codex' } }),
    });
    expect(res.status).toBe(200);
    const health = (await (await get('/api/health')).json()) as { ai: { connected: boolean; provider: string } };
    expect(health.ai).toMatchObject({ provider: 'codex', connected: true });
  });

  it('닫으면 상태가 비워진다', async () => {
    expect((await del('/api/ai/install')).status).toBe(200);
    expect((await installState()).install).toMatchObject({ provider: null, status: 'idle' });
  });

  it('깔다가 실패하면 왜 안 됐는지 남는다', async () => {
    process.env['MADI_INSTALL_CLAUDE'] = 'echo "curl: (6) Could not resolve host" 1>&2; exit 1';
    delete process.env['MADI_CLAUDE_BIN'];
    resetCliCache();
    expect((await post('/api/ai/install', { provider: 'claude' })).status).toBe(200);
    await waitFor(async () => (await installState()).install.status !== 'running', 60_000);
    const s = await installState();
    // 이 PC 에 claude 가 진짜 있을 수도 있어서(개발 머신) 둘 다 받아 준다
    expect(['failed', 'done']).toContain(s.install.status);
    if (s.install.status === 'failed') expect(s.install.error).toBeTruthy();
    await del('/api/ai/install');
    delete process.env['MADI_INSTALL_CLAUDE'];
  });

  it('하고 있는 중에 또 누르면 409', async () => {
    process.env['MADI_INSTALL_CLAUDE'] = 'sleep 5';
    expect((await post('/api/ai/install', { provider: 'claude' })).status).toBe(200);
    const again = await post('/api/ai/install', { provider: 'codex' });
    expect(again.status).toBe(409);
    expect(await errCode(again)).toBe('ai_install_busy');
    delete process.env['MADI_INSTALL_CLAUDE'];
  });

  it('로그인 창은 열 수 있는 OS 에서만 (리눅스 개발 환경은 501)', async () => {
    const res = await post('/api/ai/login', { provider: 'codex' });
    expect([200, 501]).toContain(res.status);
    if (res.status === 501) expect(await errCode(res)).toBe('ai_login_unsupported');
  });
});
