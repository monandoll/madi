/**
 * AI 연결 e2e: 도구가 PC 마다 다른 자리에 깔린다는 전제.
 * 못 찾으면 사용자가 실행 파일을 직접 알려 주고(POST /api/ai/path), 엉뚱한 파일이면 거절한다.
 * "다시 찾기"(?fresh=1)는 캐시를 버리고 처음부터 찾는다.
 */
import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AiProvidersResponse, SettingsResponse } from '@madi/shared';
import { resetCliCache } from '../src/agent/detect.js';
import { type Engine, startEngine } from '../src/engine.js';
import { FIXTURES, freePort, tempHome } from './helpers.js';

let home: string;
let engine: Engine;
const FAKE = path.join(FIXTURES, 'fake-codex.mjs');

const get = (p: string) => fetch(`${engine.url}${p}`);
const post = (p: string, body: unknown) => fetch(`${engine.url}${p}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const providers = async (fresh = false) => AiProvidersResponse.parse(await (await get(`/api/ai/providers${fresh ? '?fresh=1' : ''}`)).json()).providers;
const codexOf = async (fresh = false) => (await providers(fresh)).find((p) => p.id === 'codex')!;
const settings = async () => SettingsResponse.parse(await (await get('/api/settings')).json()).settings;

beforeAll(async () => {
  home = tempHome('madi-aipath-');
  process.env['MADI_QUIET'] = '1';
  // 이 PC 엔 codex 가 없는 셈 친다 (직접 골라 주는 길을 검사한다)
  delete process.env['MADI_CODEX_BIN'];
  resetCliCache();
  engine = await startEngine({ dataDir: home, dbPath: path.join(home, 'madi.db'), port: await freePort() });
});

afterAll(async () => {
  await engine?.stop();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('AI 도구 직접 찾아 주기', () => {
  it('직접 고른 파일이 없으면 custom 은 꺼져 있다', async () => {
    const codex = await codexOf();
    expect(codex.label).toBe('Codex');
    expect(codex.custom).toBe(false);
  });

  it('엉뚱한 파일을 고르면 거절한다 (설정도 안 바뀐다)', async () => {
    const notCli = path.join(home, '메모.txt');
    fs.writeFileSync(notCli, '이건 도구가 아니다');
    const res = await post('/api/ai/path', { provider: 'codex', path: notCli });
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe('ai_path_bad');
    expect((await settings()).ai.paths.codex).toBeNull();
  });

  it('제대로 도는 파일을 고르면 그 자리로 연결된다', async () => {
    const res = await post('/api/ai/path', { provider: 'codex', path: FAKE });
    expect(res.status).toBe(200);
    const codex = AiProvidersResponse.parse(await res.json()).providers.find((p) => p.id === 'codex')!;
    expect(codex).toMatchObject({ installed: true, custom: true, path: FAKE });
    expect(codex.version).not.toBeNull();
    expect((await settings()).ai.paths.codex).toBe(FAKE);
  });

  it('프로바이더만 바꿔도 직접 고른 자리는 그대로 남는다', async () => {
    await fetch(`${engine.url}/api/settings`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ai: { provider: 'codex' } }),
    });
    const s = await settings();
    expect(s.ai.provider).toBe('codex');
    expect(s.ai.paths.codex).toBe(FAKE);
    // 그 자리로 연결됐다고 health 도 말한다
    const health = (await (await get('/api/health')).json()) as { ai: { connected: boolean; provider: string } };
    expect(health.ai).toMatchObject({ provider: 'codex', connected: true });
  });

  it('파일이 사라지면 다시 찾기에서 끊긴 걸 알아챈다', async () => {
    const moved = path.join(home, 'codex-옮김.mjs');
    fs.copyFileSync(FAKE, moved);
    fs.chmodSync(moved, 0o755);
    expect((await post('/api/ai/path', { provider: 'codex', path: moved })).status).toBe(200);
    expect((await codexOf()).custom).toBe(true);
    fs.rmSync(moved);
    const after = await codexOf(true);
    expect(after.custom).toBe(false);
  });

  it('직접 고른 것을 지우면 다시 알아서 찾는다', async () => {
    expect((await post('/api/ai/path', { provider: 'codex', path: null })).status).toBe(200);
    expect((await settings()).ai.paths.codex).toBeNull();
    expect((await codexOf(true)).custom).toBe(false);
  });

  it('파일 선택창이 없는 환경(개발·브라우저 전용)에서는 501', async () => {
    const res = await post('/api/ai/pick', { provider: 'codex' });
    expect(res.status).toBe(501);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe('no_picker');
  });

  it('트레이 앱이 파일 선택창을 붙이면 거기서 고른 파일로 연결된다', async () => {
    engine.setFilePicker(async () => FAKE);
    const res = await post('/api/ai/pick', { provider: 'codex' });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { canceled: boolean; provider: { installed: boolean; custom: boolean; path: string } };
    expect(body.canceled).toBe(false);
    expect(body.provider).toMatchObject({ installed: true, custom: true, path: FAKE });

    // 창을 닫으면 아무것도 안 바뀐다
    engine.setFilePicker(async () => null);
    const canceled = await post('/api/ai/pick', { provider: 'codex' });
    expect(canceled.status).toBe(200);
    expect(((await canceled.json()) as { canceled: boolean }).canceled).toBe(true);
    expect((await settings()).ai.paths.codex).toBe(FAKE);
    engine.setFilePicker(undefined);
  });
});
